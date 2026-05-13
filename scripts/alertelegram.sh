#!/bin/bash

while true; do
CHECK_CONN="$(curl -k -I --head --location --connect-timeout 5 --write-out %{http_code} --silent --output /dev/null https://www.google.com)"
    if [ "${CHECK_CONN}" == "200" ]; then
        # curl -s -F chat_id=$chat_id -F document=@$TxT -F caption="$HEADER" https://api.telegram.org/bot$token/sendDocument #> /dev/null 2&>1
        RESPONSE=$(curl -s -d chat_id=$chat_id -d text="${TxT}" https://api.telegram.org/bot$token/sendMessage)
        echo "Telegram Response: $RESPONSE" >> /tmp/telegram.log
        break
    fi
done