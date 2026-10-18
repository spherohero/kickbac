'use strict';

// Dependency-free Auth0 Node 22 Action source; deploy to each corresponding trigger.
// Auth0 owns OTP generation, comparison and identity. No VerificationCheck is used.
exports.onExecutePostLogin = async (event, api) => {
  // Advisory feedback marks the latest pending provider attempt for this phone,
  // not an independently correlated attempt or an authentication decision.
  if (event?.connection?.strategy !== 'sms' || event?.user?.phone_verified !== true ||
      !validPhone(event.user.phone_number) || event?.transaction?.protocol === 'oauth2-refresh-token' ||
      event?.refresh_token != null) return;
  try {
    const secrets = config(event);
    const response = await fetch(`https://verify.twilio.com/v2/Services/${secrets.TWILIO_VERIFY_SID}/Verifications/${encodeURIComponent(event.user.phone_number)}`, {
      method: 'POST', redirect: 'error', signal: AbortSignal.timeout(8000),
      headers: {
        Authorization: 'Basic ' + Buffer.from(`${secrets.TWILIO_ACCOUNT_SID}:${secrets.TWILIO_AUTH_TOKEN}`).toString('base64'),
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: new URLSearchParams({ Status: 'approved' }),
    });
    if (!response.ok || response.status < 200 || response.status >= 300) throw new Error();
    const body = await response.json();
    if (body?.status !== 'approved') throw new Error();
  } catch {
    // Missing/expired pending attempt (including 404) must not undo Auth0 login.
    console.warn('Twilio verification feedback unavailable.');
  }
};
const SEND_ERROR = 'Phone verification delivery failed.';
const matches = (value, pattern) => typeof value === 'string' && pattern.test(value);
const validPhone = value => matches(value, /^\+[1-9][0-9]{1,14}$/) && !value.includes('\n');
function config(event) {
  const secrets = event?.secrets;
  if (!matches(secrets?.TWILIO_ACCOUNT_SID, /^AC[0-9a-fA-F]{32}$/) ||
      secrets.TWILIO_ACCOUNT_SID.length !== 34 ||
      !matches(secrets?.TWILIO_VERIFY_SID, /^VA[0-9a-fA-F]{32}$/) ||
      secrets.TWILIO_VERIFY_SID.length !== 34 ||
      !matches(secrets?.TWILIO_AUTH_TOKEN, /^[^\s]+$/)) {
    throw new Error(SEND_ERROR);
  }
  return secrets;
}
exports.onExecuteCustomPhoneProvider = async (event, api) => {
  const diagnostic = { stage: 'notification' };
  try {
    const notification = event?.notification;
    if (!notification) throw new Error(SEND_ERROR);
    const providerTest = notification.message_type === 'provider_test';
    if (notification.delivery_method !== 'text' ||
        (notification.message_type !== 'otp_verify' && !providerTest)) {
      // Auth0 drop means failed WITHOUT recovery, not successful delivery or retry.
      api.notification.drop('Unsupported phone notification.');
      return;
    }
    diagnostic.stage = 'recipient';
    if (!validPhone(notification.recipient)) throw new Error(SEND_ERROR);
    diagnostic.stage = 'otp_code';
    if (!providerTest &&
        (!matches(notification.code, /^[0-9]{6}$/) || notification.code.length !== 6)) {
      throw new Error(SEND_ERROR);
    }
    diagnostic.stage = 'configuration';
    const secrets = config(event);
    const fields = { To: notification.recipient, Channel: 'sms' };
    // Dashboard provider_test is connectivity-only: Verify generates its test code.
    // Real login always sends Auth0's exact code; this branch never authenticates.
    if (!providerTest) fields.CustomCode = notification.code;
    diagnostic.stage = 'request';
    const response = await fetch(`https://verify.twilio.com/v2/Services/${secrets.TWILIO_VERIFY_SID}/Verifications`, {
      method: 'POST', redirect: 'error', signal: AbortSignal.timeout(8000),
      headers: {
        Authorization: 'Basic ' + Buffer.from(`${secrets.TWILIO_ACCOUNT_SID}:${secrets.TWILIO_AUTH_TOKEN}`).toString('base64'),
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: new URLSearchParams(fields),
    });
    if (!response.ok || response.status < 200 || response.status >= 300) {
      diagnostic.stage = 'provider_http';
      if (Number.isInteger(response.status) && response.status >= 100 && response.status <= 599) {
        diagnostic.http_status = response.status;
      }
      try {
        const errorBody = await response.json();
        if (Number.isInteger(errorBody?.code) && errorBody.code > 0 && errorBody.code <= 99999) {
          diagnostic.provider_error_code = errorBody.code;
        }
      } catch { /* Never include an untrusted provider body or exception message. */ }
      throw new Error(SEND_ERROR);
    }
    diagnostic.stage = 'provider_response';
    const body = await response.json();
    if (body?.status !== 'pending' || body.to !== notification.recipient ||
        body.service_sid !== secrets.TWILIO_VERIFY_SID ||
        !matches(body.sid, /^VE[0-9a-fA-F]{32}$/) || body.sid.length !== 34) {
      throw new Error(SEND_ERROR);
    }
  } catch {
    // Only fixed stage names and allowlisted numeric codes may enter Auth0 logs.
    throw new Error(SEND_ERROR + ' ' + JSON.stringify(diagnostic));
  }
};
