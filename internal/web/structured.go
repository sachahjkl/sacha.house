package web

// schema.org descriptions of the pages, written as JSON-LD in the head. Search engines and answer engines read
// them to learn who the site is about and what each page is.

// object is one JSON-LD node.
type object = map[string]any

const (
	personID  = SiteURL + "/#person"
	websiteID = SiteURL + "/#website"
)

// graph wraps nodes in a JSON-LD document.
func graph(nodes ...object) object {
	return object{"@context": "https://schema.org", "@graph": nodes}
}

// person describes the author of the site.
func person() object {
	return object{
		"@type":    "Person",
		"@id":      personID,
		"name":     Me.FullName,
		"url":      SiteURL + "/",
		"image":    SiteURL + "/static/me.jpg",
		"jobTitle": "Software engineer",
		"email":    "mailto:" + Me.Mail,
		"address":  object{"@type": "PostalAddress", "addressLocality": Me.PlaceOfLiving, "addressCountry": "FR"},
		"sameAs":   []string{Me.GitHub, Me.LinkedIn},
	}
}

func website() object {
	return object{
		"@type":       "WebSite",
		"@id":         websiteID,
		"url":         SiteURL + "/",
		"name":        "sacha.house",
		"description": Me.FullName + ", software engineer. Projects, writing, and how to reach me.",
		"author":      object{"@id": personID},
		"publisher":   object{"@id": personID},
		"potentialAction": object{
			"@type":       "SearchAction",
			"target":      object{"@type": "EntryPoint", "urlTemplate": SiteURL + "/blog?q={search_term_string}"},
			"query-input": "required name=search_term_string",
		},
	}
}

// HomeStructuredData describes the home page: the site and its author.
func HomeStructuredData() any {
	return graph(website(), person())
}

// ProfileStructuredData describes a page about the author, such as /about.
func ProfileStructuredData(url string) any {
	return graph(person(), object{
		"@type":      "ProfilePage",
		"url":        url,
		"isPartOf":   object{"@id": websiteID},
		"mainEntity": object{"@id": personID},
	})
}

// BlogStructuredData describes the blog index.
func BlogStructuredData() any {
	return graph(person(), object{
		"@type":     "Blog",
		"@id":       SiteURL + "/blog#blog",
		"url":       SiteURL + "/blog",
		"name":      "sacha.house blog",
		"author":    object{"@id": personID},
		"publisher": object{"@id": personID},
		"isPartOf":  object{"@id": websiteID},
	})
}

// PostStructuredData describes a blog post and its place in the site.
func PostStructuredData(seo SEO, headline, language string) any {
	post := object{
		"@type":            "BlogPosting",
		"@id":              seo.URL + "#post",
		"url":              seo.URL,
		"mainEntityOfPage": seo.URL,
		"headline":         headline,
		"description":      seo.Description,
		"inLanguage":       language,
		"image":            object{"@type": "ImageObject", "url": seo.Image, "width": seo.ImageWidth, "height": seo.ImageHeight},
		"author":           object{"@id": personID, "name": Me.FullName},
		"publisher":        object{"@id": personID},
		"isPartOf":         object{"@id": SiteURL + "/blog#blog"},
	}
	if seo.PublishedTime != "" {
		post["datePublished"] = seo.PublishedTime
	}
	if seo.ModifiedTime != "" {
		post["dateModified"] = seo.ModifiedTime
	}
	breadcrumbs := object{
		"@type": "BreadcrumbList",
		"itemListElement": []object{
			{"@type": "ListItem", "position": 1, "name": "sacha.house", "item": SiteURL + "/"},
			{"@type": "ListItem", "position": 2, "name": "blog", "item": SiteURL + "/blog"},
			{"@type": "ListItem", "position": 3, "name": headline, "item": seo.URL},
		},
	}
	return graph(post, breadcrumbs, person())
}
