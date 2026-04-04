package main

import "core:fmt"
import "core:os"
import "core:strings"

handle_cli_args :: proc() {
	for arg in os.args[1:] {
		if arg == "-h" || arg == "--help" {
			print_help()
			os.exit(0)
		} else if arg == "-v" || arg == "--version" {
			print_version()
			os.exit(0)
		} else if arg == "-dev" {
			HOT_RELOAD = true
		} else if strings.has_prefix(arg, "--hash-password=") {
			if !load_config() {
				fmt.eprintln("Error: Failed to load config")
				os.exit(1)
			}
			if APP_CONFIG.PASSWORD_SALT == "" {
				fmt.eprintln("Error: PASSWORD_SALT must be set in config")
				os.exit(1)
			}
			password := arg[len("--hash-password="):]
			if hash, ok := hash_password(password, context.allocator); ok {
				defer delete(hash)
				fmt.println(hash)
			} else {
				fmt.eprintln("Error: Failed to hash password")
				os.exit(1)
			}
			os.exit(0)
		} else {
			fmt.eprintf("Error: Unknown argument '%s'\n\n", arg)
			print_help()
			os.exit(1)
		}
	}
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
	fmt.println()
	
	fmt.println("ENVIRONMENT VARIABLES:")
	fmt.println("  CONFIG_PATH   Path to config file (default: config.json)")
	fmt.println("  PORT          Port to listen on (default: 6969)")
	fmt.println()
	
	fmt.println("EXAMPLES:")
	fmt.println("  sacha.house")
	fmt.println("  PORT=8080 sacha.house")
	fmt.println("  CONFIG_PATH=/etc/sacha.house/config.json PORT=8080 sacha.house")
}
