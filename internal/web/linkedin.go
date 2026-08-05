package web

import (
	"encoding/json"
	"fmt"
	"io/fs"
)

type LinkedInDate struct {
	Day   int `json:"day"`
	Month int `json:"month"`
	Year  int `json:"year"`
}

func (date LinkedInDate) String() string {
	if date.Year == 0 {
		return "Present"
	}
	return fmt.Sprintf("%02d/%02d/%04d", date.Day, date.Month, date.Year)
}

type LinkedInExperience struct {
	StartsAt                  LinkedInDate  `json:"starts_at"`
	EndsAt                    *LinkedInDate `json:"ends_at"`
	Company                   string        `json:"company"`
	CompanyLinkedInProfileURL string        `json:"company_linkedin_profile_url"`
	Title                     string        `json:"title"`
	Description               string        `json:"description"`
}

func (experience LinkedInExperience) StartsOn() string {
	return experience.StartsAt.String()
}

func (experience LinkedInExperience) EndsOn() string {
	if experience.EndsAt == nil {
		return "Present"
	}
	return experience.EndsAt.String()
}

type LinkedInEducation struct {
	StartsAt                 LinkedInDate  `json:"starts_at"`
	EndsAt                   *LinkedInDate `json:"ends_at"`
	FieldOfStudy             string        `json:"field_of_study"`
	DegreeName               string        `json:"degree_name"`
	School                   string        `json:"school"`
	SchoolLinkedInProfileURL string        `json:"school_linkedin_profile_url"`
	Description              string        `json:"description"`
}

func (education LinkedInEducation) StartsOn() string {
	return education.StartsAt.String()
}

func (education LinkedInEducation) EndsOn() string {
	if education.EndsAt == nil {
		return "Present"
	}
	return education.EndsAt.String()
}

func (education LinkedInEducation) Title() string {
	return fmt.Sprintf("%s in %s", education.DegreeName, education.FieldOfStudy)
}

type LinkedInProfile struct {
	Experiences []LinkedInExperience `json:"experiences"`
	Education   []LinkedInEducation  `json:"education"`
}

type FSLinkedInProfileLoader struct {
	FS   fs.FS
	Path string
}

func (loader FSLinkedInProfileLoader) Load() (LinkedInProfile, error) {
	path := loader.Path
	if path == "" {
		path = "linkedin_profile.json"
	}
	file, err := loader.FS.Open(path)
	if err != nil {
		return LinkedInProfile{}, fmt.Errorf("open LinkedIn profile: %w", err)
	}
	defer file.Close()

	var profile LinkedInProfile
	if err := json.NewDecoder(file).Decode(&profile); err != nil {
		return LinkedInProfile{}, fmt.Errorf("decode LinkedIn profile: %w", err)
	}
	return profile, nil
}
