#!/bin/bash

## Based on work by GitHub user "serializingme":
##   https://github.com/serializingme/hpqpswdd/blob/main/Program.cs

## Treat unset variables as an error when substituting.
set -u

MAGIC_VALUE='_HPPW12_'
CIPHER='aes-256-cbc'
KEY='4a14b69632ff836b4288da79a549ed9d1c0bd377839fe2d65254710c3ebd1e33'
IV='00000000000000000000000000000000'
COMMENT=''
TARGETFILE="password.bin"
decrypt="true"
encryptedpassword=""
args=$(getopt -n "$0" -o + -l 'decrypt,encrypt' -- "$@")

eval "set -- $args"
while [ $# -ne 0 ]; do
  case "$1" in
    --decrypt)    decrypt="true";   shift ;;
    --encrypt)    decrypt="false";  shift ;;
    --) shift; break ;;
    *)  break ;;
  esac
done

if [ "$@" ]; then
  TARGETFILE="$@"
fi

if [ ${decrypt} = true ]; then
  ## Check the magic value at the start of the encrypted file.
  MAGIC_VALUE_IN_FILE="$(
  dd\
    if="${TARGETFILE}"\
    bs=1\
    count=8\
    status=none
  )"
  if [ "${MAGIC_VALUE}" != "${MAGIC_VALUE_IN_FILE}" ]; then
    echo "Unexpected magic value. Expected '${MAGIC_VALUE}', but got '${MAGIC_VALUE_IN_FILE}'." 1>&2
    exit 1
  fi

  ## Decrypt the encrypted file.
  dd\
    if="${TARGETFILE}"\
    ${COMMENT:+ skip '_HPPW12_' (8 bytes)}\
    ${COMMENT:+ skip length of encrypted string (2 bytes)}\
    skip=10\
    bs=1\
    status=none\
    | openssl enc -d -"${CIPHER}" -K "${KEY}" -iv "${IV}"
else
  # Read password from terminal input and encode it in UTF-16LE
  u16encpassword=$(IFS=$'\n' read -r -n 32 -p "Input password: " password 
  echo -n $password | iconv -f UTF-8 -t UTF-16LE | openssl enc -"${CIPHER}" -K "${KEY}" -iv "${IV}")
  # Get password size from the UTF-16LE encoded string
  passwordsize=${#u16encpassword}
  # Round passwordsize value to the next multiple of 16, to a maximum size of 80 (32 characters)
  if [ $passwordsize -le 16 ]; then
    passwordsize=16
  elif [ $passwordsize -gt 16 ] && [ $passwordsize -lt 32 ]; then
    passwordsize=32
  elif [ $passwordsize -gt 32 ] && [ $passwordsize -lt 48 ]; then
    passwordsize=48
  elif [ $passwordsize -gt 48 ] && [ $passwordsize -lt 64 ]; then
    passwordsize=64
  elif [ $passwordsize -gt 64 ] && [ $passwordsize -lt 80 ]; then
    passwordsize=80
  fi
  # "Convert" passwordsize to hex presentation
  hexsize=$(printf "%02X" "$passwordsize")
  # Print {MAGIC_VALUE}, {hexsize} and x00 to target file
  printf "${MAGIC_VALUE}\x$hexsize\x00" > "${TARGETFILE}"
  # Append the UTF-16LE encoded password to target file (must be done with echo)
  echo -n "${u16encpassword}" >> "${TARGETFILE}"
fi
