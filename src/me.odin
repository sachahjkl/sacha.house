package main

import "core:fmt"
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
	sshPublicKey:    string,
	moneroAdress:    string,
	dotfiles:        string,
	hayekfr:         string,
	hayekfrRepo:     string,
}

me_init :: proc(allocator := context.allocator) -> Me_Info {
	date_naissance, _ := time.datetime_to_time(1999, 5, 25, 0, 0, 0)
	nom := "froment"
	prenom := "sacha"

	return Me_Info {
		nom             = nom,
		prenom          = prenom,
		username        = "sachahjkl",
		fullName        = fullName(prenom, nom, allocator),
		siteTitle       = siteTitle(prenom, nom, allocator),
		age             = age(date_naissance),
		dateNaissance   = date_naissance,
		placeOfLiving   = "le Mans",
		github          = "https://github.com/sachahjkl",
		gitlab          = "https://gitlab.com/sachahjkl",
		linkedin        = "https://www.linkedin.com/in/sachafroment/",
		homepage        = "https://sacha.house",
		mail            = "sacha@sacha.house",
		curriculumVitae = "/static/cv.html",
		ethAddress      = "0xDfB091f812ea27Ca58e8f556B252f245660cba87",
		gpgPrint        = "21D64EBC463D12DFE373AE4F1EFE264F809A2118",
		sshPublicKey    = "sk-ssh-ed25519@openssh.com AAAAGnNrLXNzaC1lZDI1NTE5QG9wZW5zc2guY29tAAAAIIS8pndI4CDOvRT+oxhcluB3+N4TIOg8GTdVIHyKgZqsAAAABHNzaDo= sacha@sacha.house",
		moneroAdress    = "49ETBPrD54iCKeecWjPt2hfjciSRgptXzJc29Hd8FS97AQHzThdoxE1aE4NigAf8xYDxok1iaaGKD8a6EmUwUgkgTstDaFJ",
		dotfiles        = "https://gitlab.com/sachahjkl/dotfiles",
		hayekfr         = "https://ilone.hayek.fr/",
		hayekfrRepo     = "https://gitlab.com/bonzybuddy/bonzybuddy.gitlab.io",
	}
}

me_destroy :: proc(me: ^Me_Info, allocator := context.allocator) {
	if me == nil {
		return
	}
	delete(me.fullName, allocator)
	delete(me.siteTitle, allocator)
	me^ = {}
}

siteTitle :: proc(prenom: string, nom: string, allocator := context.allocator) -> string {
	return fmt.aprintf("Le site web personnel de %s %s", capitalize(prenom), capitalize(nom), allocator = allocator)
}

fullName :: proc(prenom: string, nom: string, allocator := context.allocator) -> string {
	return fmt.aprintf("%s %s", capitalize(prenom), capitalize(nom), allocator = allocator)
}

age :: proc(date_naissance: time.Time) -> int {
	now := time.now()
	result := time.year(now) - time.year(date_naissance)
	if time.month(now) < time.month(date_naissance) ||
	   (time.month(now) == time.month(date_naissance) && time.day(now) < time.day(date_naissance)) {
		result -= 1
	}
	return result
}
