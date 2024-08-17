#!/bin/bash

# Send AT commands to the modem
echo -e "AT+CGATT=1\r" > /dev/ttyUSB2  # Replace /dev/ttyUSB2 with the correct device path
echo -e "AT+CGDCONT=1,\"IP\",\"your_apn\"\r" > /dev/ttyUSB2
echo -e "ATD*99#\r" > /dev/ttyUSB2
