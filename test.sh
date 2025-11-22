#!/bin/bash

HPQPSWD="$(dirname "$0")/hpqpswd.sh"
PW_FILE='password.bin'

checksum()
{
	local FILE="$1"
	sha256sum -- "${FILE}" | awk '{print $1}'
}
PASSWORD='a-short-password'
"${HPQPSWD}" --encrypt <<< "${PASSWORD}"
if [ "$(checksum "${PW_FILE}")" != '9e85c7b9e551ebaf81799e7e5435c2e215c28c21f4cefddf83fc4c16db8b3665' ]
then
	echo "Encryption test failed." 1>&2
	exit 1
fi

if [ "$("${HPQPSWD}" --decrypt -- </dev/null | iconv --from-code='UTF-16LE' --to-code='UTF-8')" != "${PASSWORD}" ]
then
	echo "Decryption test failed." 1>&2
	exit 1
fi

echo "Passed."
exit 0
