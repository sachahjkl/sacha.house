package main

import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"

Cli_Action :: enum {
	Serve,
	Help,
	Version,
	Hash_Password,
	Verify_Password,
}

Cli_Options :: struct {
	hot_reload: bool,
	port:       u16,
	password:   string,
}

parse_cli_args :: proc(args: []string) -> (Cli_Options, Cli_Action, bool) {
	options := Cli_Options{port = 6969}
	if port_value := os.get_env_alloc("PORT", context.temp_allocator); port_value != "" {
		port, ok := strconv.parse_int(port_value)
		if !ok || port <= 0 || port > 65535 {
			fmt.eprintf("Error: Invalid PORT value '%s'\n", port_value)
			return {}, .Serve, false
		}
		options.port = u16(port)
	}

	action := Cli_Action.Serve
	for arg in args {
		if arg == "-h" || arg == "--help" {
			if action != .Serve do return {}, .Serve, false
			action = .Help
		} else if arg == "-v" || arg == "--version" {
			if action != .Serve do return {}, .Serve, false
			action = .Version
		} else if arg == "-dev" {
			options.hot_reload = true
		} else if strings.has_prefix(arg, "--hash-password=") {
			if action != .Serve do return {}, .Serve, false
			action = .Hash_Password
			options.password = arg[len("--hash-password="):]
		} else if strings.has_prefix(arg, "--verify-password=") {
			if action != .Serve do return {}, .Serve, false
			action = .Verify_Password
			options.password = arg[len("--verify-password="):]
		} else {
			fmt.eprintf("Error: Unknown argument '%s'\n\n", arg)
			return {}, .Serve, false
		}
	}
	return options, action, true
}

run_cli_action :: proc(action: Cli_Action, options: ^Cli_Options, config: ^Config) -> int {
	switch action {
	case .Help:
		print_help()
	case .Version:
		print_version()
	case .Hash_Password:
		if config == nil || config.PASSWORD_SALT == "" {
			fmt.eprintln("Error: PASSWORD_SALT must be set in config")
			return 1
		}
		if hash, ok := hash_password(config, options.password, context.allocator); ok {
			defer delete(hash)
			fmt.println(hash)
		} else {
			fmt.eprintln("Error: Failed to hash password")
			return 1
		}
	case .Verify_Password:
		if config == nil || !is_admin_password_configured(config) {
			fmt.eprintln("Error: ADMIN_PASSWORD_HASH and PASSWORD_SALT must be set in config")
			return 1
		}
		if !verify_password(config, options.password, config.ADMIN_PASSWORD_HASH) {
			fmt.eprintln("Password does not match")
			return 1
		}
		fmt.println("Password matches")
	case .Serve:
		return 1
	}
	return 0
}

@(private = "file")
print_version :: proc() {
	fmt.printf("%s\n", VERSION)
}

@(private = "file")
print_help :: proc() {
	fmt.println("sacha.house - Personal website server")
	fmt.printf("Version: %s\n\n", VERSION)
	fmt.println("USAGE:")
	fmt.println("  sacha.house [OPTIONS]")
	fmt.println()
	fmt.println("OPTIONS:")
	fmt.println("  -h, --help              Show this help message")
	fmt.println("  -v, --version           Show version")
	fmt.println("  -dev                    Run in development mode (enables hot reload)")
	fmt.println("  --hash-password=<pass>  Generate an argon2id hash using PASSWORD_SALT")
	fmt.println("  --verify-password=<pass>  Verify a password against the configured admin hash")
	fmt.println()
	fmt.println("ENVIRONMENT VARIABLES:")
	fmt.println("  CONFIG_PATH         Path to config file (default: config.json)")
	fmt.println("  PORT                Port to listen on (default: 6969)")
	fmt.println()
	fmt.println("EXAMPLES:")
	fmt.println("  sacha.house")
	fmt.println("  PORT=8080 sacha.house")
	fmt.println("  CONFIG_PATH=/etc/sacha.house/config.json PORT=8080 sacha.house")
}
