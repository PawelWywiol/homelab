#!/bin/bash

BASE_DIR="/home/code/sitespeed-result"

CURRENT_DATE=$(date +%s)

find "$BASE_DIR" -type d -mindepth 2 -maxdepth 2 | while read -r DIR; do
  FOLDER_NAME=$(basename "$DIR")

  if [[ "$FOLDER_NAME" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}-[0-9]{2}-[0-9]{2}-[0-9]{2}$ ]]; then
    FOLDER_DATE=$(date -d "${FOLDER_NAME:0:10}" +%s) 2>/dev/null

    DIFF_DAYS=$(((CURRENT_DATE - FOLDER_DATE) / 86400))

    if [[ $DIFF_DAYS -gt 7 ]]; then
      rm -rf "$DIR"
    fi
  fi
done
