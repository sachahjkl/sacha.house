package main

import "core:log"
import net "core:net"
import http "odin-http"

is_authorized :: proc(req: ^http.Request) -> bool {
	address := req.client.address
	client_ip_str := net.address_to_string(address)
	
	// Debug: log the client info
	log.debugf("Client address: %v, string: %s", address, client_ip_str)
	
	// localhost is all good
	if address == net.IP4_Loopback {
		return true
	}

	for ip in APP_CONFIG.ADMIN_IPS {

		if ip == client_ip_str {
			return true
		}
	}

	return false
}
