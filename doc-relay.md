# Channel Control Reference
# Relay Channel Control Architecture

```mermaid
graph TD
	Jetson[Jetson Device]
	Relay6CH[6 Channel Relay]
	Pi[Raspberry Pi]
	RelayPi[6 Channel Relay]
	User[User Terminal]
	Jetson -- Wireless (Key Embedded) --> Relay6CH
	Pi -- Wireless (Encrypted Key) --> RelayPi
	User -- SSH/Terminal --> Jetson
	Jetson -- curl (10.42.0.25) --> Relay6CH
	User -- curl ((ip):5000) --> RelayPi: "curl activates/deactivates channels"
	Pi -- curl ((ip):5000) --> RelayPi
	Relay6CH -- Channels ON/OFF --> Jetson
	RelayPi -- Channels ON/OFF --> Pi
	subgraph Jetson Profile
		Jetson
		Relay6CH
	end
	subgraph Raspberry Pi Profile
		Pi
		RelayPi
	end
```

## Jetson Profile
**Static IP:** 10.42.0.25
	- Only accessible from Jetson's terminal

6 Channel relay is connected wirelessly to Jetson device. The access key is embedded in the relay's firmware, so the relay is accessible only from the Jetson device.

### Channel Activation (ON)
```
curl http://10.42.0.25/ch1/on
curl http://10.42.0.25/ch2/on
curl http://10.42.0.25/ch3/on
curl http://10.42.0.25/ch4/on
curl http://10.42.0.25/ch5/on
curl http://10.42.0.25/ch6/on
```

### Channel Deactivation (OFF)
```
curl http://10.42.0.25/ch1/off
curl http://10.42.0.25/ch2/off
curl http://10.42.0.25/ch3/off
curl http://10.42.0.25/ch4/off
curl http://10.42.0.25/ch5/off
curl http://10.42.0.25/ch6/off
```

---

## Raspberry Pi Profile
**Variable IP, Port:** 5000
	- Raspberry Pi is the server for relay

Users do not need to SSH into the Raspberry Pi. The relay server accepts curl commands from any device on the same network, allowing channel control directly via HTTP requests.

The relay is connected wirelessly to the Raspberry Pi, with an encrypted key embedded in its firmware. It can only be accessed by the Raspberry Pi. A relay server runs inside the Raspberry Pi, allowing programmatic control of relay channels via its IP and port using curl commands as shown below.

### Channel Activation (ON)
```
curl http://(ip):5000/ch1/on
curl http://(ip):5000/ch2/on
curl http://(ip):5000/ch3/on
curl http://(ip):5000/ch4/on
curl http://(ip):5000/ch5/on
curl http://(ip):5000/ch6/on
```

### Channel Deactivation (OFF)
```
curl http://(ip):5000/ch1/off
curl http://(ip):5000/ch2/off
curl http://(ip):5000/ch3/off
curl http://(ip):5000/ch4/off
curl http://(ip):5000/ch5/off
curl http://(ip):5000/ch6/off
```
