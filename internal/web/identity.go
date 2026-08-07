package web

import "time"

// Identity contains the public identity and contact details used by the site.
type Identity struct {
	FirstName       string
	FullName        string
	SiteTitle       string
	Username        string
	BirthDate       time.Time
	PlaceOfLiving   string
	Nationality     string
	GitHub          string
	GitLab          string
	LinkedIn        string
	Mail            string
	CurriculumVitae string
	ETHAddress      string
	GPGFingerprint  string
	MoneroAddress   string
	Dotfiles        string
	HayekFR         string
	HayekFRRepo     string
}

var Me = Identity{
	FirstName:       "sacha",
	FullName:        "Sacha Froment",
	SiteTitle:       "Le site web personnel de Sacha Froment",
	Username:        "sachahjkl",
	BirthDate:       time.Date(1999, time.May, 25, 0, 0, 0, 0, time.Local),
	PlaceOfLiving:   "Marigné-Laillé",
	Nationality:     "Française",
	GitHub:          "https://github.com/sachahjkl",
	GitLab:          "https://gitlab.com/sachahjkl",
	LinkedIn:        "https://www.linkedin.com/in/sachafroment/",
	Mail:            "sacha@sacha.house",
	CurriculumVitae: "/cv",
	ETHAddress:      "0xDfB091f812ea27Ca58e8f556B252f245660cba87",
	GPGFingerprint:  "21D64EBC463D12DFE373AE4F1EFE264F809A2118",
	MoneroAddress:   "49ETBPrD54iCKeecWjPt2hfjciSRgptXzJc29Hd8FS97AQHzThdoxE1aE4NigAf8xYDxok1iaaGKD8a6EmUwUgkgTstDaFJ",
	Dotfiles:        "https://gitlab.com/sachahjkl/dotfiles",
	HayekFR:         "https://ilone.hayek.fr/",
	HayekFRRepo:     "https://gitlab.com/bonzybuddy/bonzybuddy.gitlab.io",
}

// AgeAt returns the age reached at the specified time.
func (identity Identity) AgeAt(now time.Time) int {
	age := now.Year() - identity.BirthDate.Year()
	anniversary := time.Date(now.Year(), identity.BirthDate.Month(), identity.BirthDate.Day(), 0, 0, 0, 0, now.Location())
	if now.Before(anniversary) {
		age--
	}
	return age
}
