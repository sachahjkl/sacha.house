package main

import "core:fmt"
import "core:strings"
import "core:time"

Me_Info :: struct {
	nom:             string,
	prenom:          string,
	fullName:        string,
	siteTitle:       string,
	username:        string,
	age:             int,
	dateNaissance:   time.Time,
	placeOfLiving:   string,
	github:          string,
	gitlab:          string,
	linkedin:        string,
	homepage:        string,
	mail:            string,
	curriculumVitae: string,
	ethAddress:      string,
	gpgPrint:        string,
	moneroAdress:    string,
	dotfiles:        string,
	hayekfr:         string,
	hayekfrRepo:     string,
}



ME: Me_Info

init_me :: proc(allocator := context.allocator) {

	dateNaissance, _ := time.datetime_to_time(1999, 5, 25, 0, 0, 0)
	age := age(dateNaissance)
	nom := "froment"
	prenom := "sacha"
	fullName := fmt.aprintf("%s %s", capitalize(prenom), capitalize(nom), allocator)
	siteTitle := fmt.aprintf("Le site web personnel de %s %s", capitalize(prenom), capitalize(nom), allocator)
	
	ME = Me_Info {
		nom             = nom,
		prenom          = prenom,
		username        = "sachahjkl",
		fullName        = fullName,
		siteTitle       = siteTitle,
		age             = age,
		dateNaissance   = dateNaissance,
		placeOfLiving   = "le Mans",
		github          = "https://github.com/sachahjkl",
		gitlab          = "https://gitlab.com/sachahjkl",
		linkedin        = "https://www.linkedin.com/in/sachafroment/",
		homepage        = "https://sacha.house",
		mail            = "sacha@sacha.house",
		curriculumVitae = "/cv.html",
		ethAddress      = "0xDfB091f812ea27Ca58e8f556B252f245660cba87",
		gpgPrint        = "21D64EBC463D12DFE373AE4F1EFE264F809A2118",
		moneroAdress    = "49ETBPrD54iCKeecWjPt2hfjciSRgptXzJc29Hd8FS97AQHzThdoxE1aE4NigAf8xYDxok1iaaGKD8a6EmUwUgkgTstDaFJ",
		dotfiles        = "https://gitlab.com/sachahjkl/dotfiles",
		hayekfr         = "https://ilone.hayek.fr/",
		hayekfrRepo     = "https://gitlab.com/bonzybuddy/bonzybuddy.gitlab.io",
	}

}

siteTitle :: proc( prenom: string, nom: string, allocator := context.allocator) -> string {
	return fmt.aprintf("Le site web personnel de %s %s", capitalize(prenom), capitalize(nom), allocator)
}

fullName :: proc( prenom: string, nom: string, allocator := context.allocator) -> string {
	return fmt.aprintf("%s %s", capitalize(prenom), capitalize(nom), allocator)
}

age :: proc( dateNaissance: time.Time ) -> int {
	now := time.now()
	age := time.year(now) - time.year(dateNaissance)
	if time.month(now) < time.month(dateNaissance) ||
	   (time.month(now) == time.month(dateNaissance) &&
			   time.day(now) < time.day(dateNaissance)) {
		age -= 1
	}
	return age
}
