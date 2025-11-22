#!/bin/bash

## Based on work by GitHub user "serializingme":
##   https://github.com/serializingme/hpqpswdd/blob/main/Program.cs

## Treat unset variables as an error when substituting.
set -u



SCRIPTNAME="$(basename "${0}")"

## Every file created with HPQPswd.exe starts with a fixed magical 
## value.
MAGIC_VALUE='_HPPW12_'

## The BIOS password is encrypted with AES256, with the chain block 
## cipher (CBC) for subsequent blocks.
CIPHER='aes-256-cbc'

## This is the fixed AES256 key (in hex).
KEY='4a14b69632ff836b4288da79a549ed9d1c0bd377839fe2d65254710c3ebd1e33'

## The initial vector (IV) is all zeroes.
IV='00000000000000000000000000000000'

## The default is to decrypt, but we can also encrypt (to mimic 
## HPQPswd.exe).
DECRYPT=1

## When decrypting, this is the file we will decrypt.
## 
## When encrypting, this is the file we create, containing the encrypted 
## password.
ENCRYPTED_PASSWORD_FILE='password.bin'

## We are silent by default.
VERBOSITY=0

## We can use this variable to comment inside a multiline command, using 
## "${COMMENT:+ some comment}" (expands to the empty string).
declare -r COMMENT=''



print_usage()
{
	cat <<__EOT__
Usage:
    ${SCRIPTNAME} [OPTIONS] [password_file]

Description:
    ${SCRIPTNAME} can decrypt a file encrypted by the HPQPswd.exe 
    utility. It can also mimic hpqpswd and encrypt a plain text 
    password.

Arguments:
    password_file defaults to '${ENCRYPTED_PASSWORD_FILE}'. When 
    decrypting, this is the file ${SCRIPTNAME} decrypts. When 
    encrypting, this is the file where the encrypted password is written 
    to.

Options:
    --help, -h
        Prints a brief help message and exits.

    --decrypt
        Decrypt password_file, to stdout. This is the default.

    --encrypt
        Encrypt password_file, to stdout.

    --verbose, -v
        Be verbose, by logging the value of variables for instance.
__EOT__
}



verbose()
{
	if [ "${VERBOSITY}" -ge 1 ]
	then
		echo "[${FUNCNAME[1]}:${BASH_LINENO[0]}] $*" 1>&2
	fi
}



decrypt_file()
{
	local ENCRYPTED_FILE="$1"
	verbose "ENCRYPTED_FILE=${ENCRYPTED_FILE@Q}"
	
	## Check the magic value at the start of the encrypted file.
	MAGIC_VALUE_IN_FILE="$(
		dd\
			if="${ENCRYPTED_FILE}"\
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
		if="${ENCRYPTED_FILE}"\
		${COMMENT:+ skip '_HPPW12_' (8 bytes)}\
		${COMMENT:+ skip length of encrypted string (2 bytes)}\
		skip=$[ 8 + 2 ]\
		bs=1\
		status=none\
	| openssl enc -d -"${CIPHER}" -K "${KEY}" -iv "${IV}"
	
	#if tty --silent
	#then
	#	## We are connected to a terminal, so add a newline for 
	#	## readability.
	#	echo
	#fi
}



verbose "Handling command line arguments."
OPTIONS=$(\
	getopt				\
		--options 'hv'		\
		--longoptions decrypt	\
		--longoptions encrypt	\
		--longoptions help	\
		--longoptions verbose	\
		-n "${SCRIPTNAME}"	\
		--			\
		"$@"
)
if [ $? -ne 0 ]
then
	echo "Error using getopt. Terminating..." 1>&2
	exit 1
fi
eval set -- "${OPTIONS}"
while :
do
	case "$1" in
		--decrypt)
			DECRYPT=1
			shift
			;;
		--encrypt)
			DECRYPT=0
			shift
			;;
		-h|--help)
			print_usage
			exit 0
			;;
		-v|--verbose)
			let ++VERBOSITY
			shift
			;;
		--)
			shift
			break
			;;
		*)
			echo "Internal error! (Unknown option: $1)"
			exit 1
			;;
	esac
done

if [ $# -ne 0 ]
then
	ENCRYPTED_PASSWORD_FILE="$1"
fi
verbose "ENCRYPTED_PASSWORD_FILE=${ENCRYPTED_PASSWORD_FILE@Q}"



if [ "${DECRYPT}" -ne 0 ]
then
	verbose "Mode: decrypt"
	
	if [ ! -r "${ENCRYPTED_PASSWORD_FILE}" ]
	then
		(
			echo "Error: encrypted password_file '${ENCRYPTED_PASSWORD_FILE}' is not readable. Use the password_file argument to specify an alternative name."
			echo
			print_usage
		) 1>&2
		exit 1
	fi
	decrypt_file "${ENCRYPTED_PASSWORD_FILE}"
else
	verbose "Mode: encrypt"

	## Read password from terminal.
	## 
	## 65535: The length field in the password file is 16 bit.
	IFS=$'\n' read -n 65535 -r -s -p "Input password: " PASSWORD
	if tty --silent
	then
		## We are connected to a terminal, so add a newline for 
		## readability.
		echo
	fi
	verbose "PASSWORD=${PASSWORD@Q}"
	
	## The HPQPswd.exe uses Unicode/UTF-16LE, since it is a Windows 
	## utility. Just mimic the behaviour and convert the password to 
	## UTF-16LE.
	## 
	## Bash does not properly handle null bytes, so we must convert 
	## and encrypt in one go here. Store in hex, to further avoid 
	## null bytes. And we mustn't use a herestring since that would 
	## insert an unwanted newline.
	ENCRYPTED_PASSWORD_IN_HEX="$(
		printf '%s' "${PASSWORD}"\
		| iconv\
			--from-code='UTF-8'\
			--to-code='UTF-16LE'\
		| openssl\
			enc\
			-"${CIPHER}"\
			-K "${KEY}"\
			-iv "${IV}"\
		| xxd -plain -cols 0
	)"
	verbose "ENCRYPTED_PASSWORD_IN_HEX=${ENCRYPTED_PASSWORD_IN_HEX@Q}"
	
	## Note: two hexdigits make up 1 byte.
	ENCRYPTED_PASSWORD_LENGTH=$[ "${#ENCRYPTED_PASSWORD_IN_HEX}" / 2 ]
	verbose "ENCRYPTED_PASSWORD_LENGTH=${ENCRYPTED_PASSWORD_LENGTH@Q}"
	
	verbose "Writing encrypted password file ${ENCRYPTED_PASSWORD_FILE@Q}."
	(
		## Print the header.
		printf '%s' "${MAGIC_VALUE}"
		(
			printf '%02x%02x%s'\
				$[${ENCRYPTED_PASSWORD_LENGTH} &  0xFF]\
				$[${ENCRYPTED_PASSWORD_LENGTH} >> 8   ]\
				"${ENCRYPTED_PASSWORD_IN_HEX}"
		) | xxd -plain -revert
	) > "${ENCRYPTED_PASSWORD_FILE}"
fi
