'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');
const sourcePath = path.join(__dirname, 'twilio-verify.cjs');
const secrets = {
  TWILIO_ACCOUNT_SID: 'AC' + '1'.repeat(32),
  TWILIO_AUTH_TOKEN: 'fixture-token-not-a-real-secret',
  TWILIO_VERIFY_SID: 'VA' + '2'.repeat(32),
};
const phone = '+15005550006';
const ve = 'VE' + '3'.repeat(32);
function event() {
  return { secrets: { ...secrets }, notification: {
    delivery_method: 'text', message_type: 'otp_verify', recipient: phone, code: '001234',
  } };
}
function response(overrides = {}) {
  return { ok: true, status: 201, json: async () => ({
    sid: ve, service_sid: secrets.TWILIO_VERIFY_SID, to: phone, status: 'pending',
  }), ...overrides };
}
function harness(reply = async () => response()) {
  const calls = [], warnings = [], drops = [], timeouts = [];
  const context = { exports: {}, Buffer, URLSearchParams,
    AbortSignal: { timeout: ms => { timeouts.push(ms); return AbortSignal.timeout(ms); } },
    console: { warn: (...args) => warnings.push(args) },
    fetch: async (...args) => { calls.push(args); return reply(...args); } };
  vm.runInNewContext(fs.existsSync(sourcePath) ? fs.readFileSync(sourcePath, 'utf8') : '', context);
  return { actions: context.exports, calls, warnings, drops, timeouts,
    api: { notification: { drop: reason => drops.push(reason) } } };
}
test('forwards Auth0 leading-zero OTP once with timeout and no unconfigured custom rate limit', async () => {
  const h = harness();
  assert.equal(typeof h.actions.onExecuteCustomPhoneProvider, 'function');
  await h.actions.onExecuteCustomPhoneProvider(event(), h.api);
  assert.equal(h.calls.length, 1);
  const [url, options] = h.calls[0];
  assert.equal(url, `https://verify.twilio.com/v2/Services/${secrets.TWILIO_VERIFY_SID}/Verifications`);
  assert.equal(options.method, 'POST');
  assert.equal(options.redirect, 'error');
  assert.equal(options.headers.Authorization, 'Basic ' + Buffer.from(`${secrets.TWILIO_ACCOUNT_SID}:${secrets.TWILIO_AUTH_TOKEN}`).toString('base64'));
  assert.equal(options.headers['Content-Type'], 'application/x-www-form-urlencoded');
  assert.deepEqual(Object.fromEntries(options.body), {
    To: phone, Channel: 'sms', CustomCode: '001234',
  });
  assert.ok(options.signal instanceof AbortSignal);
  assert.deepEqual(h.timeouts, [8000]);
  assert.equal(h.drops.length, 0);
});

for (const code of [undefined, 'fixture-provider-test-not-a-login-code']) {
  test(`dashboard provider_test sends a connectivity-only code without CustomCode: ${code === undefined ? 'absent code' : 'non-login code'}`, async () => {
    const h = harness(), e = event();
    e.notification.message_type = 'provider_test';
    e.notification.code = code;
    await h.actions.onExecuteCustomPhoneProvider(e, h.api);
    assert.equal(h.calls.length, 1);
    const [url, options] = h.calls[0];
    assert.equal(url, `https://verify.twilio.com/v2/Services/${secrets.TWILIO_VERIFY_SID}/Verifications`);
    assert.deepEqual(Object.fromEntries(options.body), { To: phone, Channel: 'sms' });
    assert.deepEqual(h.timeouts, [8000]);
    assert.equal(h.drops.length, 0);
  });
}

const SEND_ERROR = 'Phone verification delivery failed.';
function loginEvent() {
  return { secrets: { ...secrets }, connection: { strategy: 'sms' },
    user: { phone_verified: true, phone_number: phone }, transaction: { protocol: 'oidc-basic-profile' } };
}
const forbiddenApi = new Proxy({}, { get() { throw new Error('PostLogin must not access Auth0 API'); } });
for (const [label, change] of [
  ['missing event', () => undefined], ['missing connection', e => { delete e.connection; return e; }],
  ['other connection', e => { e.connection.strategy = 'auth0'; return e; }],
  ['unverified phone', e => { e.user.phone_verified = false; return e; }],
  ['truthy nonboolean verified', e => { e.user.phone_verified = 'true'; return e; }],
  ['missing user', e => { delete e.user; return e; }],
  ['invalid phone', e => { e.user.phone_number += '\n'; return e; }],
  ['refresh protocol', e => { e.transaction.protocol = 'oauth2-refresh-token'; return e; }],
  ['refresh token object', e => { e.refresh_token = { id: 'fixture-refresh' }; return e; }],
]) {
  test(`feedback skipped: ${label}`, async () => {
    const h = harness();
    await h.actions.onExecutePostLogin(change(loginEvent()), forbiddenApi);
    assert.equal(h.calls.length, 0);
    assert.equal(h.warnings.length, 0);
  });
}
for (const [label, reply, change] of [
  ['network', async () => { throw new Error(`${phone} ${secrets.TWILIO_AUTH_TOKEN}`); }],
  ...[404, 429, 500].map(status => [`HTTP ${status}`, async () => response({ ok: false, status })]),
  ['malformed response', async () => response({ json: async () => null })],
  ['invalid config', async () => response(), e => { e.secrets.TWILIO_VERIFY_SID = 'invalid'; return e; }],
]) {
  test(`feedback failure cannot undo login or disclose details: ${label}`, async () => {
    const h = harness(reply), e = change ? change(loginEvent()) : loginEvent();
    await h.actions.onExecutePostLogin(e, forbiddenApi);
    assert.equal(h.calls.length, label === 'invalid config' ? 0 : 1);
    assert.deepEqual(h.warnings, [['Twilio verification feedback unavailable.']]);
  });
}
test('verified SMS login sends advisory approval by encoded phone without changing Auth0 state', async () => {
  const h = harness(async () => response({ status: 200, json: async () => ({
    sid: ve, service_sid: secrets.TWILIO_VERIFY_SID, to: phone, status: 'approved',
  }) }));
  assert.equal(typeof h.actions.onExecutePostLogin, 'function');
  const e = loginEvent(), before = JSON.stringify(e);
  await h.actions.onExecutePostLogin(e, forbiddenApi);
  assert.equal(JSON.stringify(e), before);
  assert.equal(h.calls.length, 1);
  const [url, options] = h.calls[0];
  assert.equal(url, `https://verify.twilio.com/v2/Services/${secrets.TWILIO_VERIFY_SID}/Verifications/%2B15005550006`);
  assert.equal(options.method, 'POST');
  assert.equal(options.redirect, 'error');
  assert.equal(options.headers.Authorization, 'Basic ' + Buffer.from(`${secrets.TWILIO_ACCOUNT_SID}:${secrets.TWILIO_AUTH_TOKEN}`).toString('base64'));
  assert.deepEqual(Object.fromEntries(options.body), { Status: 'approved' });
  assert.deepEqual(h.timeouts, [8000]);
  assert.equal(h.warnings.length, 0);
});
for (const [label, reply] of [
  ['network failure', async () => { throw new Error(`private ${phone} 001234 ${secrets.TWILIO_AUTH_TOKEN}`); }],
  ['timeout', async () => { throw new DOMException('private abort details', 'TimeoutError'); }],
  ...[302, 400, 401, 404, 429, 500].map(status => [`HTTP ${status}`, async () => response({ ok: false, status, json: async () => { throw new Error('body must not be read'); } })]),
  ['invalid JSON', async () => response({ json: async () => { throw new Error('private body'); } })],
  ...[null, {}, { status: 'approved' }, { status: 'pending', to: '+15005550007' },
    { status: 'pending', service_sid: 'VA' + '4'.repeat(32) }, { status: 'pending', sid: 'bad' }].map((body, i) =>
    [`malformed response ${i}`, async () => response({ json: async () => ({ sid: ve, to: phone, service_sid: secrets.TWILIO_VERIFY_SID, ...body }) })]),
]) {
  // Empty/null fixtures must not inherit the valid response fields.
  test(`delivery sanitizes errors without retry: ${label}`, async () => {
    const h = harness(label === 'malformed response 0' || label === 'malformed response 1'
      ? async () => response({ json: async () => label.endsWith('0') ? null : {} }) : reply);
    await sanitizedFailure(h.actions.onExecuteCustomPhoneProvider(event(), h.api));
    assert.equal(h.calls.length, 1);
    assert.equal(h.warnings.length, 0);
  });
}
async function sanitizedFailure(promise) {
  await assert.rejects(promise, error => {
    assert.ok(error.message.startsWith(SEND_ERROR + ' '));
    const detail = JSON.parse(error.message.slice(SEND_ERROR.length + 1));
    assert.ok(['notification', 'recipient', 'otp_code', 'configuration', 'request', 'provider_http', 'provider_response'].includes(detail.stage));
    assert.ok(Object.keys(detail).every(key => ['stage', 'http_status', 'provider_error_code'].includes(key)));
    assert.equal(error.message.includes(phone), false);
    assert.equal(error.message.includes(secrets.TWILIO_AUTH_TOKEN), false);
    assert.equal(error.message.includes('001234'), false);
    assert.equal(error.cause, undefined);
    assert.deepEqual(Object.keys(error), []);
    return true;
  });
}
test('delivery error reports only provider HTTP status and numeric error code', async () => {
  const h = harness(async () => response({ ok: false, status: 403,
    json: async () => ({ code: 21608, message: `${phone} ${secrets.TWILIO_AUTH_TOKEN} 001234` }) }));
  await assert.rejects(h.actions.onExecuteCustomPhoneProvider(event(), h.api), error => {
    assert.equal(error.message, SEND_ERROR + ' ' + JSON.stringify({ stage: 'provider_http', http_status: 403, provider_error_code: 21608 }));
    return true;
  });
  assert.equal(h.calls.length, 1);
});
test('provider-test error identifies invalid recipient without exposing the number', async () => {
  const h = harness(), e = event();
  e.notification.message_type = 'provider_test';
  e.notification.recipient = 'private invalid recipient';
  await assert.rejects(h.actions.onExecuteCustomPhoneProvider(e, h.api), error => {
    assert.equal(error.message, SEND_ERROR + ' ' + JSON.stringify({ stage: 'recipient' }));
    return true;
  });
  assert.equal(h.calls.length, 0);
});
for (const [label, change] of [
  ['missing event', () => undefined],
  ['missing notification', e => ({ secrets: e.secrets })],
  ...['15005550006', '+05005550006', '+1', '+1234567890123456', '+15005550006\n', '+15005550006\r', '+15005550006\u2028', ' +15005550006', 15005550006, null].map(value =>
    [`invalid phone ${JSON.stringify(value)}`, e => { e.notification.recipient = value; return e; }]),
  ...[123456, '12345', '1234567', '１２３４５６', '123456\n', undefined].map(value =>
    [`invalid code ${JSON.stringify(value)}`, e => { e.notification.code = value; return e; }]),
  ...['TWILIO_ACCOUNT_SID', 'TWILIO_VERIFY_SID', 'TWILIO_AUTH_TOKEN'].flatMap(key =>
    ['', undefined, ' ', 'bad\nvalue', 'fixture\n'].map(value => [`invalid config ${key} ${JSON.stringify(value)}`, e => { e.secrets[key] = value; return e; }])),
  ['missing secrets', e => { delete e.secrets; return e; }],
]) {
  test(`delivery fails closed without fetch: ${label}`, async () => {
    const h = harness();
    await sanitizedFailure(h.actions.onExecuteCustomPhoneProvider(change(event()), h.api));
    assert.equal(h.calls.length, 0);
    assert.equal(h.warnings.length, 0);
  });
}
for (const [key, value] of [
  ['delivery_method', 'voice'], ['delivery_method', 'email'], ['delivery_method', undefined],
  ['message_type', 'blocked_account'], ['message_type', 'password_breach'],
  ['message_type', 'change_password'], ['message_type', 'phone_enrollment'], ['message_type', undefined],
]) {
  test(`unsupported ${key}=${value} is explicitly dropped, never sent`, async () => {
    const h = harness(), e = event();
    e.notification[key] = value;
    await h.actions.onExecuteCustomPhoneProvider(e, h.api);
    assert.equal(h.calls.length, 0);
    assert.deepEqual(h.drops, ['Unsupported phone notification.']);
  });
}
