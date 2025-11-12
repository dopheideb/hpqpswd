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
ENCRYPTEDFILE="${1:-}"



## Print usage if necessary.
if [\
	"${ENCRYPTEDFILE}" = ''\
	-o\
	"${ENCRYPTEDFILE}" = '--help'\
	-o\
	"${ENCRYPTEDFILE}" = '-h' \
]
then
	cat <<-__EOT__
Usage:
    $0 file-encrypted-with-hpqpswd-file.bin

The file should be encrypted with the HPQPswd.exe utility.
	__EOT__
	exit 0
fi



## Check the magic value at the start of the encrypted file.
MAGIC_VALUE_IN_FILE="$(
	dd\
		if="${ENCRYPTEDFILE}"\
		bs=1\
		count=8\
		status=none
)"
if [ "${MAGIC_VALUE}" != "${MAGIC_VALUE_IN_FILE}" ]
then
	echo "Unexpected magic value. Expected '${MAGIC_VALUE}', but got '${MAGIC_VALUE_IN_FILE}'." 1>&2
	exit 1
fi



## Decrypt the encrypted file.
dd\
	if="${ENCRYPTEDFILE}"\
	\
	${COMMENT:+ skip '_HPPW12_' (8 bytes)}\
	${COMMENT:+ skip length of encrypted string (2 bytes)}\
	skip=10\
	bs=1\
	status=none\
| openssl\
	enc\
	\
	${COMMMENT:+ '-d' means decrypt}\
	-d\
	-"${CIPHER}"\
	-K "${KEY}"\
	-iv "${IV}"
OPENSSL_EXITCODE="${PIPESTATUS[1]}"



if tty --silent
then
	## We are connected to a terminal, so add a newline for 
	## readability.
	echo
fi

exit "${OPENSSL_EXITCODE}"
