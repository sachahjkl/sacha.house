package main

import "core:fmt"
import "core:log"
import "core:time"
import "core:time/datetime"
import "core:time/timezone"

// NOTE(Sacha Froment):
// - This is a global variable that is used to store the timezone.
// - It is initialized in the `init_timezone` function.
// - Used for the whole duration of the program, no need to free it.
TIMEZONE: ^datetime.TZ_Region

init_timezone :: proc() -> bool {
	if tz, ok := timezone.region_load("Europe/Paris"); ok {
		TIMEZONE = new_clone(tz)^
		return true
	}
	return false
}


format_date :: proc(date: datetime.DateTime) -> string {
	local_date := timezone.datetime_to_tz(date, TIMEZONE)

	if local_date.year == 0 {
		return "Present"
	}
	// format the date as DD/MM/YYYY
	return fmt.tprintf("%02d/%02d/%04d", local_date.day, local_date.month, local_date.year)
}

format_time :: proc(date: datetime.DateTime) -> string {
	local_date := timezone.datetime_to_tz(date, TIMEZONE)
	hour, minute, second := local_date.hour, local_date.minute, local_date.second

	return fmt.tprintf("%02d:%02d:%02d", hour, minute, second)
}

iso8601_to_datetime :: proc(t: string) -> (datetime.DateTime, bool) {
	t, _ := time.iso8601_to_time_utc(t)
	return time.time_to_datetime(t)
}

duration_between :: proc(start, end: time.Time) -> time.Duration {
	return time.Duration(time.time_to_unix_nano(end) - time.time_to_unix_nano(start))
}
