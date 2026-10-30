package web

import "strings"

type CareerExperience struct {
	Period      string
	Role        string
	Company     string
	Context     string
	Summary     string
	Highlights  []CareerHighlight
	Details     []CareerDetail
	Environment string
	FullOnly    bool
}

type CareerHighlight struct {
	Lead string
	Text string
}

func hl(lead, text string) CareerHighlight {
	return CareerHighlight{Lead: lead, Text: text}
}

type CareerDetail struct {
	Title string
	Text  string
}

type CareerEducation struct {
	Period      string
	Degree      string
	School      string
	Notes       []CareerHighlight
}

type CareerProject struct {
	Name        string
	URL         string
	Summary     string
	Description string
	Stack       string
}

type CareerGroup struct {
	Title string
	Items []string
}

type CareerPublication struct {
	Date  string
	Title string
	URL   string
}

type CareerProfile struct {
	Language           string
	OtherLanguage      string
	OtherLanguageLabel string
	Summary            string
	Nationality        string
	AgeLabel           string
	LocationLabel      string
	ContactLabel       string
	ExperienceLabel    string
	EducationLabel     string
	ProjectsLabel      string
	CatalogLabel       string
	PublicationsLabel  string
	LanguagesLabel     string
	PrintLabel         string
	ResumeLabel        string
	CVLabel            string
	EnvironmentLabel   string
	Experiences        []CareerExperience
	Education          []CareerEducation
	Projects           []CareerProject
	Catalog            []CareerGroup
	Publications       []CareerPublication
	Languages          []string
}

type CareerPageData struct {
	PageData
	Identity
	Age     int
	Full    bool
	Profile CareerProfile
}

func Career(language string) CareerProfile {
	if language == "en" {
		return careerEN()
	}
	return careerFR()
}

func careerPath(full bool, language string) string {
	path := "/resume"
	if full {
		path = "/cv"
	}
	if language == "en" {
		return path + "?lang=en"
	}
	return path
}

func joinCareerItems(items []string) string {
	return strings.Join(items, " · ")
}

func careerFR() CareerProfile {
	return CareerProfile{
		Language: "fr", OtherLanguage: "en", OtherLanguageLabel: "English",
		Summary:     "Ingénieur logiciel avec plus de six ans d'expérience, dont trois en alternance, sur des applications métier .NET et Angular. Je prends en charge, souvent de ma propre initiative, les chantiers de fond qui conditionnent la qualité des livraisons : migrations de frameworks, réduction des temps de tests et d'intégration continue, performance applicative, restructuration des socles techniques et design system. Je mesure avant d'agir et je conduis ces chantiers seul, de la conception à l'adoption par l'équipe.",
		Nationality: "Français", AgeLabel: "ans", LocationLabel: "Marigné-Laillé, France",
		ContactLabel: "Contact", ExperienceLabel: "Expérience", EducationLabel: "Études",
		ProjectsLabel: "Projets sélectionnés", CatalogLabel: "Catalogue de projets",
		PublicationsLabel: "Publications", LanguagesLabel: "Langues", PrintLabel: "Imprimer / PDF",
		ResumeLabel: "CV", CVLabel: "CV complet", EnvironmentLabel: "Stack",
		Experiences: []CareerExperience{
			{
				Period: "Depuis avril 2025", Role: "Ingénieur logiciel", Company: "Catamania", Context: "Mission chez le leader français des services funéraires",
				Summary: "Modernisation, performance et fiabilité d'une suite d'applications métier de gestion des commandes (ASP.NET Core, Angular, SQL Server), au sein d'une organisation d'environ quinze développeurs. Au-delà des développements prévus, j'ai traité seul et de ma propre initiative le travail de fond qui conditionne la fiabilité des livraisons : modernisation du front, performance des tests et de la CI, restructuration de la couche visuelle et design system.",
				Highlights: []CareerHighlight{
					hl("Migration d'Angular 17 à 21 menée seul,", "avec des codemods AST pour les transformations non couvertes par les outils officiels."),
					hl("Migration de plus de 900 tests de Jest vers Vitest,", "parallélisés : environ 20 minutes → 30 secondes."),
					hl("Pipeline front ramené de 30 à 5-6 minutes,", "soit environ 2 heures d'attente gagnées par jour et près de 8 heures les jours de pointe. Pipeline back : 20 → 7 minutes (chantier partagé)."),
					hl("Changelog automatique basé sur les work items Azure DevOps,", "intégré à la CI/CD et à l'application pour suivre les livraisons."),
					hl("Cascades de chargement supprimées", "après profilage : une page complexe passe d'environ 5 secondes à 1 seconde."),
					hl("Couche visuelle incohérente restructurée en un thème unifié,", "design system étendu avec des pages de démonstration."),
					hl("Système transverse de permissions co-conçu,", "en production, utilisé par Angular et les API .NET."),
				},
				Details: []CareerDetail{
					{Title: "Modernisation du front-end", Text: "De ma propre initiative, j'ai mené seul la migration d'Angular 17 à Angular 21, de l'analyse à la mise en production. Pour les transformations que les outils officiels ne couvrent pas, j'ai écrit des codemods AST qui ont automatisé la réécriture du code. J'ai ensuite migré la suite de plus de 900 tests de Jest vers Vitest et je l'ai parallélisée : son exécution est passée d'environ 20 minutes à 30 secondes."},
					{Title: "Intégration continue", Text: "J'ai mesuré puis optimisé seul le pipeline front, qui est passé de 30 minutes à 5 ou 6 minutes. Avec environ cinq exécutions par jour et jusqu'à dix-neuf les jours de pointe, cela représente près de deux heures d'attente gagnées chaque jour, et près de huit heures les jours chargés. J'ai également contribué à ramener le pipeline back de 20 à 7 minutes, dans le cadre d'un chantier partagé (environ neuf exécutions par jour)."},
					{Title: "Changelog automatique", Text: "J'ai mis en place un journal des livraisons généré par la CI/CD à partir des work items Azure DevOps. Il fonctionne en ajout seul : le pipeline reprend l'artefact changelog.json de la version précédente et y ajoute les work items livrés depuis la dernière version taggée. Le fichier est intégré à l'application, ce qui permet de suivre les livraisons depuis l'interface."},
					{Title: "Performance applicative", Text: "J'ai profilé une page complexe, identifié des cascades de chargement séquentielles, puis je les ai supprimées : son affichage est passé d'environ cinq secondes à une seconde."},
					{Title: "Thème et design system", Text: "J'ai repris de ma propre initiative une couche visuelle chaotique : composants instables ou difficiles à intégrer, couleurs disparates d'un écran à l'autre. Je l'ai restructurée en un thème cohérent fondé sur des variables partagées. Sur cette base, j'ai étendu et fiabilisé les composants du design system, chacun accompagné d'une page de démonstration, ce qui accélère le développement et garantit la cohérence entre les équipes."},
					{Title: "Retour en temps réel", Text: "J'ai fait passer en temps réel plusieurs envois, en particulier les échanges interapplicatifs. L'utilisateur voit désormais le résultat immédiatement, sans rafraîchir la page. J'ai aussi enrichi les états d'erreur pour qu'un échec soit compréhensible sans passer par le support."},
					{Title: "Recherche d'agence", Text: "J'ai refondu le parcours de changement d'agence, qui reposait sur une recherche fragile par code de ville. Je l'ai remplacé par une recherche floue instantanée (Fuse.js) sur la ville, l'adresse et les autres attributs de l'agence."},
					{Title: "Profils et permissions", Text: "J'ai co-conçu un système transverse de permissions, désormais en production à la place de contrôles dispersés propres à chaque fonctionnalité. Le calcul des droits combine les groupes Active Directory, les données de l'utilisateur en base et la session, puis les rapproche de profils hiérarchiques et de règles dynamiques. Le même résultat pilote l'affichage dans Angular et les contrôles d'accès des API .NET. Le modèle est validé par de nombreux cas positifs et négatifs générés à partir des conditions d'accès, et revu avec les responsables produit. J'ai aussi participé à la normalisation des mécanismes d'authentification."},
					{Title: "Intégration de prestations externes", Text: "J'ai intégré un système d'évaluation d'articles de commande à partir d'API de prestataires externes : règles de gestion, suivi et affichage des statuts, gestion des erreurs et journalisation des échanges."},
					{Title: "Socle .NET", Text: "De ma propre initiative, j'ai centralisé les règles de build dans Directory.Build.props et verrouillé les dépendances. J'ai aussi évalué .NET 10 et Nix pour préparer les prochaines évolutions sans perturber la production."},
					{Title: "Contexte", Text: "La suite échange des données au moyen d'API JSON, de flux interapplicatifs et d'un bus de services, avec l'introduction progressive de CQRS. Elle est développée par plusieurs équipes, soit environ quinze développeurs et quatre à cinq interlocuteurs produit, en Agile avec Azure DevOps. En l'absence d'équipe de test dédiée, les développeurs portent les tests automatisés."},
				},
				Environment: "C#, .NET 7/8, ASP.NET Core, Angular 17–21, TypeScript, SQL Server, Azure App Service, Azure DevOps, Active Directory, Fuse.js, Jest, Vitest",
			},
			{
				Period: "Janvier 2023 – mars 2025", Role: "Ingénieur logiciel", Company: "AViSTO", Context: "Mission Alstom",
				Summary: "Mission de deux ans sur les outils de configuration des systèmes ferroviaires embarqués. J'ai conçu et implémenté seul une CLI .NET 8 utilisée en production, préparé la migration de plusieurs dizaines de projets de NAnt vers MSBuild et fait évoluer des applications WinForms en .NET Framework.",
				Highlights: []CareerHighlight{
					hl("CLI .NET 8 de production conçue et implémentée seul :", "formats binaires, validation XSD, chiffrement et signature."),
					hl("Migration NAnt → MSBuild préparée", "pour plusieurs dizaines de projets C#, outillage d'automatisation compris."),
					hl("Applications WinForms (.NET Framework 4) maintenues,", "évolutions sécurisées par des tests NUnit unitaires et d'intégration."),
				},
				Details: []CareerDetail{
					{Title: "CLI de production", Text: "À partir de spécifications techniques détaillant les formats binaires, la taille des champs et les règles d'échange, j'ai conçu et implémenté seul l'outil. La CLI produit des archives de données techniques destinées à certains systèmes du train, valide les documents XML selon des schémas spécialisés, contrôle la cohérence des données, puis chiffre et signe les fichiers. J'ai conçu des résultats typés, des diagnostics et des codes de sortie qui rendent chaque échec exploitable par les utilisateurs comme par les traitements automatisés."},
					{Title: "Migration du système de build", Text: "J'ai préparé la migration du système historique de NAnt vers MSBuild sur plusieurs dizaines de projets C#. Au-delà de la traduction des scripts, j'ai analysé le graphe de dépendances, éliminé les risques de cycles, revu certains découpages et raccordé les modules de génération de code au cycle de build de Visual Studio."},
					{Title: "Automatisation et transmission", Text: "J'ai écrit des outils qui automatisent les transformations répétitives tout en traitant explicitement les particularités de chaque projet. J'ai intégré le résultat à Visual Studio et à GitLab CI, puis documenté l'architecture cible pour que l'équipe poursuive le chantier."},
					{Title: "Qualité", Text: "J'ai sécurisé les évolutions des outils de configuration et de comparaison par des tests NUnit unitaires et d'intégration, dans un environnement réunissant .NET Framework 4 et .NET 8."},
				},
				Environment: "C#, .NET Framework 4, .NET 8, WinForms, NUnit, XML Schema, chiffrement, signature, NAnt, MSBuild, Visual Studio, GitLab CI",
			},
			{
				Period: "Septembre 2019 – juin 2022", Role: "Assistant systèmes d'information en alternance", Company: "AG2R La Mondiale",
				Summary: "Alternance de trois ans dans l'équipe de cartographie du système d'information. J'ai conçu et maintenu seul un framework TypeScript déployé sur près de 50 000 pages, puis conduit la migration de MEGA HOPEX V2R1 vers V5 jusqu'à sa mise en production, comme co-chef de projet MOE.",
				Highlights: []CareerHighlight{
					hl("Framework TypeScript de 25 modules conçu,", "déployé sur près de 50 000 pages et maintenu seul jusqu'à mon départ."),
					hl("Migration MEGA HOPEX V2R1 → V5 conduite jusqu'à la mise en production,", "comme co-chef de projet MOE."),
				},
				Details: []CareerDetail{
					{Title: "Refonte du front-end", Text: "J'ai conçu un framework TypeScript de 25 modules et environ 4 900 lignes pour refondre près de 50 000 pages générées par la plateforme. Son architecture apporte gestion d'état, hooks, montage sur un DOM existant et chargement dynamique, tout en conservant les échanges XML, JSON, SOAP et REST du système en place."},
					{Title: "Déploiement et maintenance", Text: "J'ai déployé cette couche progressivement à la place d'une interface ancienne et contrainte en largeur. J'ai restructuré la navigation et les vues consacrées aux données métier, aux applications et aux technologies, puis ajouté des liens contextuels entre des informations auparavant isolées. J'en ai assuré seul la maintenance et les évolutions jusqu'à mon départ."},
					{Title: "Build et intégration", Text: "J'ai construit l'outillage autour de Webpack 5, Babel, TypeScript et Sass, et uniformisé les builds et les déploiements entre environnements avec des scripts PowerShell. J'ai aussi fait évoluer les traitements d'extraction, d'import et d'API en VBScript et C#."},
					{Title: "Migration de MEGA HOPEX", Text: "Comme co-chef de projet MOE, j'ai conduit la migration de V2R1 vers V5 : personnalisations, dépendances, scripts et infrastructure d'exploitation (IIS, SSO SAML2, sauvegardes et restauration SQL). J'ai pris en charge la réalisation technique, le cadrage, la préparation des opérations et la documentation de reprise, jusqu'à la mise en production."},
				},
				Environment: "TypeScript, Webpack 5, Babel, Sass, PowerShell, C#, VBScript, XML, JSON, SOAP, REST, MEGA HOPEX, IIS, SAML2, SQL Server",
			},
			{
				Period: "Juin – octobre 2022", Role: "Product Owner", Company: "AG2R La Mondiale", FullOnly: true,
				Summary: "Rôle temporaire consacré à l'inventaire et à la cartographie des technologies, serveurs et logiciels du système d'information, dans la continuité du travail mené sur la plateforme HOPEX.",
			},
			{
				Period: "Avril – août 2019", Role: "Administrateur systèmes stagiaire", Company: "Italic", FullOnly: true,
				Summary: "Administration de 5 à 10 VPS OVH sous Linux pour l'hébergement de sites clients. Automatisation en Bash de la configuration, des sauvegardes, des déploiements et de la supervision d'une infrastructure LAMP.",
				Details: []CareerDetail{
					{Title: "Automatisation et exploitation", Text: "Des scripts Bash ont automatisé la configuration des serveurs, les sauvegardes, les déploiements et la supervision. L'exploitation reposait sur Apache, PHP, MySQL ou MariaDB, SSH et rsync. Une étude complémentaire a exploré l'automatisation de relevés bancaires par EBICS avec Ruby."},
				},
				Environment: "Linux, Bash, Apache, PHP, MySQL/MariaDB, SSH, rsync, OVH, Ruby, EBICS",
			},
		},
		Education: []CareerEducation{
			{Period: "2019 – 2022", Degree: "Diplôme d'ingénieur en informatique, spécialité systèmes d'information", School: "CNAM", Notes: []CareerHighlight{
				hl("Mémoire :", "gestion de l'obsolescence, cadrage, conduite du changement et migration vers MEGA HOPEX V5, comme co-chef de projet MOE."),
				hl("Rapport d'activité (2019 – 2020) :", "modernisation de la plateforme de cartographie AG2R, développée en C# avec Graphviz, JavaScript et VBScript."),
				hl("Étude (2020 – 2021) :", "comparaison de REST hypermédia et de GraphQL, avec un prototype Svelte réalisé seul en trois jours et demi pour mesurer l'impact sur le client web."),
			}},
			{Period: "2017 – 2019", Degree: "DUT Informatique", School: "IUT Paris Descartes", Notes: []CareerHighlight{
				hl("Programme :", "développement logiciel, web, données, systèmes et réseaux ; participation à la Nuit de l'info 2018."),
			}},
		},
		Projects: []CareerProject{
			{Name: "wren", URL: "https://github.com/sachahjkl/wren", Summary: "Navigateur web écrit en Odin où WebAssembly est le seul moteur d'exécution, JavaScript compris : moteur JS compilé en Wasm et exécuté par Wasmtime, moteur CSS et mise en page, rendu GPU Direct3D 11.", Description: "Navigateur web écrit en Odin où WebAssembly est le seul moteur d'exécution. Les scripts d'une page tournent dans un moteur JavaScript écrit en Odin, compilé en Wasm et exécuté par Wasmtime, une instance par page, avec limite mémoire et délai. Les pages peuvent aussi appeler directement des modules Wasm ; les API web sont décrites une fois en Web IDL, et un générateur produit les liaisons hôte, le SDK, la documentation et les tests de conformité. Le reste est un vrai moteur : HTML (Lexbor), CSS moderne, shadow DOM, mises en page block, inline, flex, grid et table, rendu GPU Direct3D 11 et texte DirectWrite.", Stack: "Odin, WebAssembly, Wasmtime, Direct3D 11, Web IDL"},
			{Name: "sacha.house", URL: "https://github.com/sachahjkl/sacha.house", Summary: "Site personnel et moteur de publication en Go, avec composants templ, navigation Datastar, authentification WebAuthn et déploiement Nix.", Description: "Je développe mon site personnel et son moteur de publication en Go. Le serveur utilise templ pour les composants, Datastar pour la navigation progressive et WebAuthn pour authentifier l'accès à l'interface d'administration. Le build, les livraisons et le déploiement reposent sur Nix.", Stack: "Go, templ, Datastar, Tailwind CSS, WebAuthn, Nix"},
			{Name: "nixconfig", URL: "https://github.com/sachahjkl/nixconfig", Summary: "Infrastructure NixOS déclarative utilisée pour reconstruire plusieurs machines et services à partir de modules partagés.", Description: "Je maintiens une infrastructure NixOS déclarative afin de rendre mes systèmes reproductibles et de limiter les écarts de configuration entre les machines. Les mêmes modules permettent de reconstruire quatre configurations, dont trois machines physiques et un environnement WSL. Le dépôt contient 123 modules flake-parts, 94 modules NixOS et 24 entrées de flake ; il configure 31 hôtes virtuels et 20 conteneurs.", Stack: "Nix, NixOS, flake-parts, systemd, conteneurs"},
			{Name: "albumator", URL: "https://github.com/sachahjkl/albumator", Description: "J'ai développé cette application de dépôt, de classement et de consultation d'images avec Svelte 5 et SvelteKit.", Stack: "Svelte 5, SvelteKit, Tailwind CSS"},
			{Name: "clockin.sacha.house", URL: "https://github.com/sachahjkl/clockin.sacha.house", Description: "Application personnelle de pointage conçue autour d'une interaction minimale : un bouton enregistre le temps et des statistiques restituent l'activité. L'identité ne requiert ni courriel ni mot de passe ; un identifiant court généré par le serveur suffit pour retrouver les données. L'application réunit une SPA Angular 22, une API Fastify, Drizzle et SQLite dans un service NixOS reproductible.", Stack: "Angular 22, Fastify, TypeScript, Drizzle ORM, SQLite, NixOS"},
			{Name: "jav", URL: "https://github.com/sachahjkl/jav", Description: "CLI écrite en Rust pour apporter à l'écosystème Java une expérience cohérente proche de celle de la CLI .NET. Elle détecte les projets Maven, Gradle ou Java simples et unifie les commandes de création, build, test, exécution, nettoyage, diagnostic et mise à jour. Dix modèles couvrent les usages courants, de la console à Spring, avec un flake Nix généré par défaut pour fournir un environnement reproductible.", Stack: "Rust, Java, Maven, Gradle, Nix, GitHub Actions"},
		},
		Catalog: []CareerGroup{
			{Title: "Applications et sites", Items: []string{"lanblaster.sacha.house", "froment.software", "chat.sacha.house", "wthhyb.sacha.house", "albumator", "clockin.sacha.house", "marketing.sacha.house", "button.sacha.house", "cool.sacha.house", "react-training.sacha.house"}},
			{Title: "Outils et systèmes", Items: []string{"nixconfig", "dotfiles", "jav", "dw", "MEGA_CLI", "subtitles-translater", "mrtg-autoinstall", "electrorustogram"}},
			{Title: "Expérimentations", Items: []string{"htmx.sacha.house", "Rust Testground", "Win32 Trainer", "Rudimentary File Explorer"}},
			{Title: "Projets académiques", Items: []string{"Portefeuille Ethereum Android en Kotlin", "Musées du monde en RDF/SPARQL et Symfony", "Prototype REST hypermédia contre GraphQL en Svelte", "Bibliothèque JSP", "services web dynamiques", "simulation de propagation virale", "emploi du temps web", "algorithmes de sac à dos", "messagerie Java", "Sudoku C#"}},
		},
		Publications: []CareerPublication{
			{Date: "Novembre 2025", Title: "Design draft for chat.sacha.house", URL: "/blog/rust-rewrite-xmaybex"},
			{Date: "Novembre 2025", Title: "HTTP Benchmark of sacha.house", URL: "/blog/sacha-house-benchmark"},
			{Date: "Octobre 2025", Title: "Homelab Architecture Diagram", URL: "/blog/homelab-architecture-diagram"},
			{Date: "Mars 2023", Title: "Make your Windows PowerShell experience feel like Linux", URL: "/blog/powershell-like-linux"},
		},
		Languages: []string{"Français : langue maternelle", "Anglais : bilingue, usage professionnel et technique"},
	}
}

func careerEN() CareerProfile {
	profile := careerFR()
	profile.Language = "en"
	profile.OtherLanguage = "fr"
	profile.OtherLanguageLabel = "Français"
	profile.Summary = "Software engineer with more than six years of experience, including a three-year apprenticeship, on .NET and Angular business applications. I take ownership, often on my own initiative, of the foundational work that determines delivery quality: framework migrations, faster tests and continuous integration, application performance, platform restructuring, and design systems. I measure before acting and drive this work on my own, from design through team adoption."
	profile.Nationality = "French"
	profile.AgeLabel = "years old"
	profile.ContactLabel = "Contact"
	profile.ExperienceLabel = "Experience"
	profile.EducationLabel = "Education"
	profile.ProjectsLabel = "Selected projects"
	profile.CatalogLabel = "Project catalog"
	profile.PublicationsLabel = "Publications"
	profile.LanguagesLabel = "Languages"
	profile.PrintLabel = "Print / PDF"
	profile.ResumeLabel = "Résumé"
	profile.CVLabel = "Full CV"
	profile.EnvironmentLabel = "Stack"
	profile.Experiences = []CareerExperience{
		{
			Period: "Since April 2025", Role: "Software engineer", Company: "Catamania", Context: "Assignment with France's leading funeral services group",
			Summary: "Modernization, performance, and reliability of a suite of order-management business applications (ASP.NET Core, Angular, SQL Server) in an organization of about fifteen developers. Beyond planned feature work, I took on, alone and on my own initiative, the foundational work that determines delivery reliability: front-end modernization, test and CI performance, visual-layer restructuring, and the design system.",
			Highlights: []CareerHighlight{
				hl("Angular 17 to 21 migration led alone,", "with AST codemods for transformations not covered by official tooling."),
				hl("900+ tests migrated from Jest to Vitest", "and parallelized: about 20 minutes → 30 seconds."),
				hl("Front-end pipeline cut from 30 to 5–6 minutes,", "saving about 2 hours of waiting per day and nearly 8 hours on peak days. Back-end pipeline: 20 → 7 minutes (shared effort)."),
				hl("Automatic changelog based on Azure DevOps work items,", "built into the CI/CD pipeline and the application to track deliveries."),
				hl("Loading cascades removed", "after profiling: a complex page went from about 5 seconds to 1 second."),
				hl("Inconsistent visual layer restructured into a unified theme,", "design system extended with demo pages."),
				hl("Cross-cutting permission system co-designed,", "in production, used by Angular and the .NET APIs."),
			},
			Details: []CareerDetail{
				{Title: "Front-end modernization", Text: "On my own initiative, I led the Angular 17 to Angular 21 migration alone, from analysis to production. For transformations not covered by official tooling, I wrote AST codemods that automated the code rewrite. I then migrated the 900+ test suite from Jest to Vitest and parallelized it, reducing runtime from about 20 minutes to 30 seconds."},
				{Title: "Continuous integration", Text: "I measured and optimized the front-end pipeline on my own, bringing it from 30 minutes down to 5 or 6. With about five runs per day and up to nineteen on peak days, this saves nearly two hours of waiting every day and nearly eight hours on busy days. I also helped reduce the back-end pipeline from 20 to 7 minutes as part of a shared effort (about nine runs per day)."},
				{Title: "Automatic changelog", Text: "I set up a delivery log generated by the CI/CD pipeline from Azure DevOps work items. It is append-only: the pipeline takes the changelog.json artifact of the previous version and adds the work items delivered since the last tagged version. The file is built into the application, so deliveries can be followed from the interface."},
				{Title: "Application performance", Text: "I profiled a complex page, identified sequential loading cascades, and removed them, reducing its load time from about five seconds to one second."},
				{Title: "Theme and design system", Text: "On my own initiative, I took over a chaotic visual layer: unstable or hard-to-integrate components and inconsistent colors from one screen to the next. I restructured it into a coherent theme built on shared variables. On that foundation, I extended and hardened the design-system components, each with a demo page, which speeds up development and keeps teams consistent."},
				{Title: "Real-time feedback", Text: "I moved several submissions to real time, especially inter-application exchanges. Users now see the outcome immediately without refreshing the page. I also enriched error states so failures are understandable without going through support."},
				{Title: "Agency search", Text: "I redesigned the agency-change workflow, which relied on an unreliable city-code search. I replaced it with instant fuzzy search (Fuse.js) across city, address, and other agency attributes."},
				{Title: "Profiles and permissions", Text: "I co-designed a cross-cutting permission system, now in production in place of checks scattered across individual features. Permission calculation combines Active Directory groups, user data from the database, and session information, then matches them against hierarchical profiles and dynamic rules. The same result drives rendering in Angular and access control in the .NET APIs. The model is validated through numerous generated positive and negative cases and reviewed with product owners. I also helped standardize the authentication mechanisms."},
				{Title: "External service integration", Text: "I integrated an order-item evaluation system through external providers' APIs: business rules, status tracking and display, error handling, and exchange logging."},
				{Title: ".NET platform", Text: "On my own initiative, I centralized build rules in Directory.Build.props and locked dependencies. I also evaluated .NET 10 and Nix to prepare future changes without disrupting production."},
				{Title: "Context", Text: "The suite exchanges data through JSON APIs, inter-application flows, and a service bus, with CQRS being introduced progressively. Several teams develop it, about fifteen developers and four to five product representatives, working in Agile with Azure DevOps. Without a dedicated QA team, developers own automated testing."},
			},
			Environment: "C#, .NET 7/8, ASP.NET Core, Angular 17–21, TypeScript, SQL Server, Azure App Service, Azure DevOps, Active Directory, Fuse.js, Jest, Vitest",
		},
		{
			Period: "January 2023 – March 2025", Role: "Software engineer", Company: "AViSTO", Context: "Alstom assignment",
			Summary: "Two-year assignment on configuration tools for embedded railway systems. I designed and implemented a production .NET 8 CLI on my own, prepared several dozen projects for migration from NAnt to MSBuild, and evolved WinForms applications on .NET Framework.",
			Highlights: []CareerHighlight{
				hl("Production .NET 8 CLI designed and implemented alone:", "binary formats, XSD validation, encryption, and signing."),
				hl("NAnt → MSBuild migration prepared", "for several dozen C# projects, including automation tooling."),
				hl("WinForms applications (.NET Framework 4) maintained,", "with changes secured by NUnit unit and integration tests."),
			},
			Details: []CareerDetail{
				{Title: "Production CLI", Text: "Working from technical specifications that defined binary layouts, field sizes, and exchange rules, I designed and implemented the tool on my own. It produces technical-data archives for selected train systems, validates XML documents against specialized schemas, checks data consistency, then encrypts and signs the resulting files. I designed typed results, diagnostics, and exit codes that make failures actionable for both users and automated processing."},
				{Title: "Build-system migration", Text: "I prepared the legacy system for migration from NAnt to MSBuild across several dozen C# projects. Beyond translating scripts, I analyzed the dependency graph, eliminated cycle risks, revised some project boundaries, and wired code-generation modules into the Visual Studio build lifecycle."},
				{Title: "Automation and handover", Text: "I wrote tools that automate repetitive transformations while handling project-specific behavior explicitly. I integrated the result with Visual Studio and GitLab CI, then documented the target architecture so the team could continue the migration."},
				{Title: "Quality", Text: "I secured changes to configuration and comparison tools with NUnit unit and integration tests in an environment combining .NET Framework 4 and .NET 8."},
			},
			Environment: "C#, .NET Framework 4, .NET 8, WinForms, NUnit, XML Schema, encryption, signing, NAnt, MSBuild, Visual Studio, GitLab CI",
		},
		{
			Period: "September 2019 – June 2022", Role: "Information systems assistant, apprenticeship", Company: "AG2R La Mondiale",
			Summary: "Three-year apprenticeship in the information-system mapping team. I designed and solely maintained a TypeScript framework deployed across almost 50,000 pages, then led the MEGA HOPEX V2R1-to-V5 migration through production as joint technical project lead.",
			Highlights: []CareerHighlight{
				hl("25-module TypeScript framework designed,", "deployed across almost 50,000 pages and solely maintained until I left."),
				hl("MEGA HOPEX V2R1 → V5 migration led through production", "as joint technical project lead."),
			},
			Details: []CareerDetail{
				{Title: "Front-end redesign", Text: "I designed a 25-module, 4,900-line TypeScript framework to redesign almost 50,000 pages generated by the platform. Its architecture adds state management, hooks, mounting on an existing DOM, and dynamic loading while preserving the existing XML, JSON, SOAP, and REST exchanges."},
				{Title: "Deployment and maintenance", Text: "I rolled this layer out progressively to replace an old fixed-width interface. I restructured navigation and the views for business data, applications, and technologies, then added contextual links between previously isolated information. I remained its sole maintainer until leaving the company."},
				{Title: "Build and integration", Text: "I built the toolchain around Webpack 5, Babel, TypeScript, and Sass, and standardized builds and deployments across environments with PowerShell scripts. I also evolved extraction, import, and API processing in VBScript and C#."},
				{Title: "MEGA HOPEX migration", Text: "As joint technical project lead, I drove the V2R1 to V5 migration: customizations, dependencies, scripts, and operational infrastructure (IIS, SAML2 SSO, backups, and SQL restoration). I handled implementation, scoping, operational preparation, and handover documentation through production deployment."},
			},
			Environment: "TypeScript, Webpack 5, Babel, Sass, PowerShell, C#, VBScript, XML, JSON, SOAP, REST, MEGA HOPEX, IIS, SAML2, SQL Server",
		},
		{Period: "June – October 2022", Role: "Product Owner", Company: "AG2R La Mondiale", FullOnly: true, Summary: "Temporary role focused on the inventory and mapping of information-system technologies, servers, and software, extending the work performed on the HOPEX platform."},
		{Period: "April – August 2019", Role: "Systems administration intern", Company: "Italic", FullOnly: true, Summary: "Administered 5 to 10 Linux VPS instances hosting customer websites. Bash automation covered configuration, backups, deployments, and monitoring for the LAMP infrastructure.", Details: []CareerDetail{{Title: "Automation and operations", Text: "Bash scripts automated server configuration, backups, deployments, and monitoring. Operations relied on Apache, PHP, MySQL or MariaDB, SSH, and rsync. Additional research explored Ruby-based automation of EBICS banking statements."}}, Environment: "Linux, Bash, Apache, PHP, MySQL/MariaDB, SSH, rsync, OVH, Ruby, EBICS"},
	}
	profile.Education = []CareerEducation{
		{Period: "2019 – 2022", Degree: "Engineering degree in computer science, information systems", School: "CNAM", Notes: []CareerHighlight{
			hl("Thesis:", "obsolescence management, scoping, change management, and migration to MEGA HOPEX V5, as joint technical project lead."),
			hl("Activity report (2019 – 2020):", "modernization of the AG2R information-system mapping platform, built with C#, Graphviz, JavaScript, and VBScript."),
			hl("Study (2020 – 2021):", "comparison of hypermedia REST and GraphQL, with a Svelte prototype built alone in three and a half days to assess the impact on the web client."),
		}},
		{Period: "2017 – 2019", Degree: "Two-year university degree in computer science", School: "IUT Paris Descartes", Notes: []CareerHighlight{
			hl("Curriculum:", "software development, web, data, systems, and networks; took part in Nuit de l'Info 2018."),
		}},
	}
	profile.Projects = []CareerProject{
		{Name: "wren", URL: "https://github.com/sachahjkl/wren", Summary: "Web browser written in Odin where WebAssembly is the only execution engine, JavaScript included: a JS engine compiled to Wasm and run by Wasmtime, a CSS and layout engine, Direct3D 11 GPU rendering.", Description: "Web browser written in Odin where WebAssembly is the only execution engine. Page scripts run in a JavaScript engine written in Odin, compiled to Wasm and run by Wasmtime, one instance per page with a memory cap and a deadline. Pages can also call Wasm modules directly; the web APIs are described once in Web IDL, and a generator produces the host bindings, the guest SDK, the documentation, and the conformance tests. Everything else is a real engine: HTML (Lexbor), modern CSS, shadow DOM, block, inline, flex, grid, and table layout, Direct3D 11 GPU rendering, and DirectWrite text.", Stack: "Odin, WebAssembly, Wasmtime, Direct3D 11, Web IDL"},
		{Name: "sacha.house", URL: "https://github.com/sachahjkl/sacha.house", Summary: "Personal website and publishing engine in Go, with templ components, Datastar navigation, WebAuthn authentication, and Nix deployment.", Description: "I develop my personal website and publishing engine in Go. The server uses templ for components, Datastar for progressive navigation, and WebAuthn to authenticate access to the administration interface. Nix handles builds, releases, and deployment.", Stack: "Go, templ, Datastar, Tailwind CSS, WebAuthn, Nix"},
		{Name: "nixconfig", URL: "https://github.com/sachahjkl/nixconfig", Summary: "Declarative NixOS infrastructure used to rebuild several machines and services from shared modules.", Description: "I maintain declarative NixOS infrastructure to make my systems reproducible and limit configuration drift between machines. Shared modules rebuild four configurations, including three physical computers and one WSL environment. The repository contains 123 flake-parts modules, 94 NixOS modules, and 24 flake inputs; it configures 31 virtual hosts and 20 containers.", Stack: "Nix, NixOS, flake-parts, systemd, containers"},
		{Name: "albumator", URL: "https://github.com/sachahjkl/albumator", Description: "I developed this image upload, organization, and browsing application with Svelte 5 and SvelteKit.", Stack: "Svelte 5, SvelteKit, Tailwind CSS"},
		{Name: "clockin.sacha.house", URL: "https://github.com/sachahjkl/clockin.sacha.house", Description: "Personal clock-in application designed around minimal interaction: one button records time and statistics summarize activity. Identity requires neither email nor password; a short server-generated identifier is enough to retrieve the data. The application packages an Angular 22 SPA, a Fastify API, Drizzle, and SQLite as a reproducible NixOS service.", Stack: "Angular 22, Fastify, TypeScript, Drizzle ORM, SQLite, NixOS"},
		{Name: "jav", URL: "https://github.com/sachahjkl/jav", Description: "Rust CLI that brings a consistent, .NET-like command-line experience to Java development. It detects Maven, Gradle, and plain Java projects and unifies project creation, build, test, run, clean, diagnostics, and upgrades. Ten templates cover common use cases from console applications to Spring, with a Nix flake generated by default for a reproducible environment.", Stack: "Rust, Java, Maven, Gradle, Nix, GitHub Actions"},
	}
	profile.Catalog = []CareerGroup{
		{Title: "Applications and websites", Items: profile.Catalog[0].Items},
		{Title: "Tools and systems", Items: profile.Catalog[1].Items},
		{Title: "Experiments", Items: profile.Catalog[2].Items},
		{Title: "Academic projects", Items: []string{"Read-only Ethereum wallet for Android in Kotlin", "World museums with RDF/SPARQL and Symfony", "REST hypermedia versus GraphQL prototype in Svelte", "JSP library", "dynamic web services", "virus propagation simulation", "web timetable", "knapsack algorithms", "Java messaging application", "C# Sudoku"}},
	}
	profile.Publications[0].Date = "November 2025"
	profile.Publications[1].Date = "November 2025"
	profile.Publications[2].Date = "October 2025"
	profile.Publications[3].Date = "March 2023"
	profile.Languages = []string{"French: native", "English: bilingual professional and technical proficiency"}
	return profile
}
