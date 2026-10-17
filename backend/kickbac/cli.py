import argparse

from .db import initialize
from .settings import Settings


def main():
    parser = argparse.ArgumentParser()
    parser.add_subparsers(dest="command", required=True).add_parser("init-db")
    parser.parse_args()
    initialize(Settings.from_env().db_path)
    print("Database initialized (schema 1).")


if __name__ == "__main__":
    main()
