import os
from dataclasses import dataclass
from pathlib import Path


@dataclass
class Settings:
    db_path: Path
    auth0_domain: str = ""
    auth0_audience: str = ""

    @classmethod
    def from_env(cls):
        return cls(
            Path(os.environ.get("KICKBAC_DB_PATH", "data/kickbac.sqlite3")),
            os.environ.get("AUTH0_DOMAIN", ""),
            os.environ.get("AUTH0_AUDIENCE", ""),
        )
