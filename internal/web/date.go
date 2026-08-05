package web

import (
	"time"
	_ "time/tzdata"
)

var ParisLocation = mustLoadLocation("Europe/Paris")

func mustLoadLocation(name string) *time.Location {
	location, err := time.LoadLocation(name)
	if err != nil {
		panic(err)
	}
	return location
}

func FormatDate(value time.Time) string {
	if value.IsZero() {
		return "Present"
	}
	return value.In(ParisLocation).Format("02/01/2006")
}

func FormatTime(value time.Time) string {
	return value.In(ParisLocation).Format("15:04:05")
}

func LocalYear(value time.Time) int {
	return value.In(ParisLocation).Year()
}
