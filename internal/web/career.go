package web

import "strings"

type CareerExperience struct {
	Period      string
	Role        string
	Company     string
	Context     string
	Summary     string
	Details     []CareerDetail
	Environment string
	FullOnly    bool
}

type CareerDetail struct {
	Title string
	Text  string
}

type CareerEducation struct {
	Period      string
	Degree      string
	School      string
	Description string
	FullOnly    bool
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
	Title              string
	Summary            string
	Nationality        string
	AgeLabel           string
	LocationLabel      string
	ContactLabel       string
	ExperienceLabel    string
	EducationLabel     string
	SkillsLabel        string
	ProjectsLabel      string
	CatalogLabel       string
	PublicationsLabel  string
	LanguagesLabel     string
	PrintLabel         string
	ResumeLabel        string
	CVLabel            string
	ProfileLabel       string
	SelectedLabel      string
	EnvironmentLabel   string
	Experiences        []CareerExperience
	Education          []CareerEducation
	Skills             []CareerGroup
	ResumeSkills       []string
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
		Title:       "Ingénieur logiciel et systèmes",
		Summary:     "Ingénieur logiciel et systèmes spécialisé dans la modernisation d'applications métier et de leurs chaînes de développement. Mon parcours couvre le développement .NET et web, l'outillage, la performance et l'exploitation Linux, avec une attention constante portée à la fiabilité et aux temps de cycle.",
		Nationality: "Français", AgeLabel: "ans", LocationLabel: "Marigné-Laillé, France",
		ContactLabel: "Contact", ExperienceLabel: "Expérience", EducationLabel: "Formation",
		SkillsLabel: "Compétences", ProjectsLabel: "Projets sélectionnés", CatalogLabel: "Catalogue de projets",
		PublicationsLabel: "Publications", LanguagesLabel: "Langues", PrintLabel: "Imprimer / PDF",
		ResumeLabel: "CV", CVLabel: "CV complet", ProfileLabel: "Profil", SelectedLabel: "Principales réalisations", EnvironmentLabel: "Environnement technique",
		Experiences: []CareerExperience{
			{
				Period: "Depuis avril 2025", Role: "Ingénieur logiciel", Company: "Catamania", Context: "Mission OGF",
				Summary: "Mission sur plusieurs applications internes dédiées à la gestion des commandes et à l'exploitation. L'essentiel du travail porte sur le développement de fonctionnalités et la correction d'anomalies en ASP.NET Core, Angular et SQL Server. Les principales réalisations comprennent l'intégration de prestations externes, la refonte du changement d'agence et la conception partagée d'un système transverse de permissions. L'équipe travaille en Agile avec Azure DevOps.",
				Details: []CareerDetail{
					{Title: "Organisation", Text: "Le développement est réparti entre plusieurs équipes applicatives, avec des changements de périmètre au fil des priorités. L'ensemble réunit environ quinze développeurs et quatre à cinq interlocuteurs produit. La conception technique est portée au sein des équipes de développement ; en l'absence d'une équipe de test dédiée, la recette fonctionnelle revient aux représentants produit et les développeurs prennent en charge les tests automatisés nécessaires."},
					{Title: "Intégration de prestations externes", Text: "Un système d'évaluation d'articles de commande a été intégré à partir d'API fournies par des prestataires externes. Le développement couvre l'application des règles de gestion, le suivi et l'affichage des statuts, la gestion des erreurs et la journalisation des échanges, afin de rendre le traitement compréhensible et exploitable dans les applications internes."},
					{Title: "Changement d'agence", Text: "Le parcours a été repris pour remplacer un mécanisme ancien, limité à une recherche fragile par code de ville. La nouvelle recherche utilise Fuse.js pour appliquer un fuzzy matching sur les différentes dimensions d'une agence, notamment la ville et l'adresse, puis restitue des résultats utilisables dans le parcours métier."},
					{Title: "Architecture applicative", Text: "La suite échange des données entre plusieurs applications au moyen d'API JSON sur HTTP, de flux interapplicatifs et d'un bus de services. L'architecture combine des opérations CRUD éprouvées avec l'introduction progressive de CQRS pour mieux séparer les responsabilités de lecture, d'écriture et de traitement métier."},
					{Title: "Profils et permissions", Text: "Une contribution importante a porté sur la conception partagée d'un système transverse, désormais utilisé en production à la place de contrôles historiques dispersés et propres à chaque fonctionnalité. Le calcul des droits agrège des groupes issus d'Active Directory, des données liées à l'utilisateur en base et des informations de session. Ces composantes sont rapprochées de déclarations de profils hiérarchiques, de leurs permissions et de règles dynamiques complémentaires. Le résultat pilote à la fois l'affichage conditionnel dans Angular et les contrôles d'accès des API .NET."},
					{Title: "Validation des droits", Text: "La validation du modèle repose sur de nombreux cas positifs et négatifs générés à partir des conditions d'accès. Des échanges réguliers avec les responsables produit ont permis de vérifier que la généralisation du système préservait les règles métier couvertes par l'ancien fonctionnement."},
					{Title: "Modernisation du front-end", Text: "La migration d'Angular 17 vers Angular 21 a été menée de bout en bout, avec la création de codemods AST pour automatiser les transformations absentes des outils officiels. La suite de plus de 900 tests a été transférée de Jest vers Vitest et parallélisée ; son exécution est passée d'environ 20 minutes à 30 secondes."},
					{Title: "Performance et intégration continue", Text: "Le même travail de mesure et d'optimisation a ramené le pipeline front de 30 minutes à 5 ou 6 minutes, et le pipeline back de 20 à 7 minutes dans le cadre d'un chantier partagé. Sur l'application, le profilage puis la suppression de cascades de chargement ont réduit l'affichage d'une page complexe d'environ cinq secondes à une seconde."},
					{Title: "Socle .NET", Text: "Le socle a été consolidé par la centralisation des règles dans Directory.Build.props et le verrouillage des dépendances. Des travaux exploratoires autour de Nix et de .NET 10 ont permis d'évaluer les prochaines évolutions sans perturber les chemins de production."},
				},
				Environment: "C#, .NET 7/8, ASP.NET Core, Angular 17–21, TypeScript, SQL Server, Azure App Service, Azure DevOps, Active Directory, Fuse.js, Jest, Vitest",
			},
			{
				Period: "Janvier 2023 – mars 2025", Role: "Ingénieur logiciel", Company: "AViSTO", Context: "Mission Alstom",
				Summary: "Mission de deux ans chez Alstom sur des outils de configuration de systèmes ferroviaires embarqués. Maintenance d'applications WinForms en .NET Framework, conception autonome d'une CLI .NET 8 utilisée en production et préparation de la migration de plusieurs dizaines de projets de NAnt vers MSBuild.",
				Details: []CareerDetail{
					{Title: "CLI de production", Text: "À partir de spécifications techniques détaillant les formats binaires, la taille des champs et les règles d'échange, j'ai assuré seul la conception et l'implémentation de l'outil. La CLI produit des archives de données techniques destinées à certains systèmes du train, valide les documents XML selon des schémas spécialisés, contrôle la cohérence des données, puis chiffre et signe les fichiers. Les résultats typés, les diagnostics et les codes de sortie rendent chaque échec exploitable par les utilisateurs comme par les traitements automatisés."},
					{Title: "Migration du système de build", Text: "Le système historique a été préparé pour une migration de NAnt vers MSBuild à l'échelle de plusieurs dizaines de projets C#. Le chantier ne se limitait pas à traduire les scripts : il a fallu analyser le graphe de dépendances, réduire les risques de cycles, revoir certains découpages et raccorder correctement les modules de génération de code au cycle de construction de Visual Studio."},
					{Title: "Automatisation et reprise", Text: "Des outils ont automatisé les transformations répétitives tout en laissant un traitement explicite pour les particularités de chaque projet. L'intégration avec Visual Studio et GitLab CI, ainsi que la documentation de l'architecture cible, ont préparé la reprise du chantier par l'équipe."},
					{Title: "Qualité", Text: "Les évolutions des outils de configuration et de comparaison ont été sécurisées par des tests NUnit, au niveau unitaire comme au niveau intégration, dans un environnement réunissant .NET Framework 4 et .NET 8."},
				},
				Environment: "C#, .NET Framework 4, .NET 8, WinForms, NUnit, XML Schema, chiffrement, signature, NAnt, MSBuild, Visual Studio, GitLab CI",
			},
			{
				Period: "Septembre 2019 – juin 2022", Role: "Assistant systèmes d'information en alternance", Company: "AG2R La Mondiale",
				Summary: "Alternance au sein de l'équipe de cartographie du système d'information. Conception et maintenance d'un framework TypeScript déployé progressivement sur près de 50 000 pages, évolution des traitements C# et VBScript, puis participation à la migration de MEGA HOPEX V2R1 vers V5 jusqu'à sa mise en production.",
				Details: []CareerDetail{
					{Title: "Refonte du front-end", Text: "La modernisation a conduit à la conception d'un framework TypeScript de 25 modules et environ 4 900 lignes, chargé de refondre près de 50 000 pages générées par la plateforme. Son architecture apporte gestion d'état, hooks, montage sur un DOM existant et chargement dynamique, tout en conservant les échanges XML, JSON, SOAP et REST du système en place."},
					{Title: "Déploiement et maintenance", Text: "Déployée progressivement au cours de l'alternance, cette couche a remplacé une interface ancienne et contrainte en largeur. Elle a restructuré la navigation et les vues consacrées aux données métier, aux applications et aux technologies, puis ajouté des liens contextuels entre des informations auparavant isolées. J'en ai assuré seul la maintenance et les évolutions jusqu'à mon départ."},
					{Title: "Build et intégration", Text: "L'outillage associé a été construit autour de Webpack 5, Babel, TypeScript et Sass. Des scripts PowerShell ont ensuite uniformisé les builds et les déploiements entre les environnements. Les traitements d'extraction, d'import et d'API ont continué à évoluer en VBScript et C#."},
					{Title: "Migration de MEGA HOPEX", Text: "La migration de V2R1 vers V5 a mobilisé les personnalisations, les dépendances, les scripts et l'infrastructure d'exploitation : IIS, SSO SAML2, sauvegardes et restauration SQL. Le travail associait réalisation technique, cadrage, préparation des opérations et documentation de reprise, jusqu'à la mise en production de la nouvelle version."},
				},
				Environment: "TypeScript, Webpack 5, Babel, Sass, PowerShell, C#, VBScript, XML, JSON, SOAP, REST, MEGA HOPEX, IIS, SAML2, SQL Server",
			},
			{
				Period: "Juin – octobre 2022", Role: "Product Owner", Company: "AG2R La Mondiale", FullOnly: true,
				Summary: "Rôle temporaire consacré à l'inventaire et à la cartographie des technologies, serveurs et logiciels du système d'information, dans la continuité du travail mené sur la plateforme HOPEX.",
			},
			{
				Period: "Avril – août 2019", Role: "Administrateur systèmes stagiaire", Company: "Italic",
				Summary: "Administration de 5 à 10 VPS OVH sous Linux pour l'hébergement de sites clients. Automatisation en Bash de la configuration, des sauvegardes, des déploiements et de la supervision d'une infrastructure LAMP.",
				Details: []CareerDetail{
					{Title: "Automatisation et exploitation", Text: "Des scripts Bash ont automatisé la configuration des serveurs, les sauvegardes, les déploiements et la supervision. L'exploitation reposait sur Apache, PHP, MySQL ou MariaDB, SSH et rsync. Une étude complémentaire a exploré l'automatisation de relevés bancaires par EBICS avec Ruby."},
				},
				Environment: "Linux, Bash, Apache, PHP, MySQL/MariaDB, SSH, rsync, OVH, Ruby, EBICS",
			},
		},
		Education: []CareerEducation{
			{Period: "2019 – 2022", Degree: "Diplôme d'ingénieur en informatique, spécialité systèmes d'information", School: "Conservatoire national des arts et métiers", Description: "Mon mémoire portait sur la gestion de l'obsolescence, le cadrage, la conduite du changement et la migration réelle vers MEGA HOPEX V5. J'intervenais comme co-chef de projet MOE."},
			{Period: "2020 – 2021", Degree: "Étude de REST hypermédia et GraphQL", School: "Conservatoire national des arts et métiers", Description: "J'ai comparé les deux modèles d'API, puis réalisé seul un prototype Svelte en trois jours et demi afin d'évaluer leurs contraintes et leur impact sur le client web.", FullOnly: true},
			{Period: "2019 – 2020", Degree: "Modernisation d'une plateforme de cartographie", School: "Conservatoire national des arts et métiers", Description: "Le premier rapport d'activité documentait la modernisation de la plateforme AG2R et les développements réalisés en C# avec Graphviz, JavaScript et VBScript.", FullOnly: true},
			{Period: "2017 – 2019", Degree: "DUT Informatique", School: "IUT Paris Descartes", Description: "La formation couvrait le développement logiciel, le web, les données, les systèmes et les réseaux. J'ai participé à la Nuit de l'Info 2018."},
		},
		Skills: []CareerGroup{
			{Title: "Développement applicatif", Items: []string{"Je travaille principalement avec C#, .NET Framework, .NET 7/8, ASP.NET Core, WinForms, TypeScript, Angular et Go. Je conçois des applications métier web, des applications de bureau, des CLI et des outils d'intégration. Svelte 5 et SvelteKit complètent cette pratique dans mes projets personnels."}},
			{Title: "Tests et performance", Items: []string{"J'utilise Vitest, Jest et NUnit pour les tests unitaires et d'intégration. Je profile les applications et les chaînes de build avant d'agir sur les temps d'exécution, les accès aux données ou la parallélisation."}},
			{Title: "Données, build et livraison", Items: []string{"Je travaille avec SQL Server, SQLite, XML, JSON, SOAP, REST et GraphQL. Mes chaînes de livraison utilisent notamment Azure DevOps, GitLab CI, GitHub Actions, MSBuild, NAnt, Webpack 5, Babel, PowerShell, Nix, Docker et Azure App Service."}},
			{Title: "Systèmes", Items: []string{"J'administre des systèmes Linux et NixOS avec systemd, des conteneurs, de la virtualisation, Apache, des sauvegardes et de la supervision. Bash, SSH et rsync servent à automatiser leur exploitation."}},
			{Title: "Pratiques professionnelles", Items: []string{"Je travaille en équipe Agile avec des interlocuteurs produit, métier et techniques. Je rédige des spécifications, des documents d'architecture, des descriptions d'interfaces et des procédures d'exploitation. Mon parcours comprend aussi le cadrage, la conduite du changement et la présentation de sujets techniques."}},
		},
		ResumeSkills: []string{
			"Développement applicatif : C#, .NET, Angular, TypeScript, Go et SQL pour des applications web, desktop et des outils en ligne de commande.",
			"Qualité et livraison : tests automatisés, profilage, Azure DevOps, GitLab CI, MSBuild, Webpack, Docker, Linux et NixOS.",
			"Pratiques professionnelles : travail en équipe Agile, échanges produit et métier, documentation technique, cadrage et conduite du changement.",
		},
		Projects: []CareerProject{
			{Name: "sacha.house", URL: "https://github.com/sachahjkl/sacha.house", Summary: "Site personnel et moteur de publication en Go, avec composants templ, navigation Datastar, authentification WebAuthn et déploiement Nix.", Description: "Je développe mon site personnel et son moteur de publication en Go. Le serveur utilise templ pour les composants, Datastar pour la navigation progressive et WebAuthn pour authentifier l'accès à l'interface d'administration. Le build, les livraisons et le déploiement reposent sur Nix.", Stack: "Go, templ, Datastar, Tailwind CSS, WebAuthn, Nix"},
			{Name: "nixconfig", URL: "https://github.com/sachahjkl/nixconfig", Summary: "Infrastructure NixOS déclarative utilisée pour reconstruire plusieurs machines et services à partir de modules partagés.", Description: "Je maintiens une infrastructure NixOS déclarative afin de rendre mes systèmes reproductibles et de limiter les écarts de configuration entre les machines. Les mêmes modules permettent de reconstruire quatre configurations, dont trois machines physiques et un environnement WSL. Le dépôt contient 123 modules flake-parts, 94 modules NixOS et 24 entrées de flake ; il configure 31 hôtes virtuels et 20 conteneurs.", Stack: "Nix, NixOS, flake-parts, systemd, conteneurs"},
			{Name: "albumator", URL: "https://github.com/sachahjkl/albumator", Description: "J'ai développé cette application de dépôt, de classement et de consultation d'images avec Svelte 5 et SvelteKit.", Stack: "Svelte 5, SvelteKit, Tailwind CSS"},
			{Name: "clockin.sacha.house", URL: "https://github.com/sachahjkl/clockin.sacha.house", Description: "Application personnelle de pointage conçue autour d'une interaction minimale : un bouton enregistre le temps et des statistiques restituent l'activité. L'identité ne requiert ni courriel ni mot de passe ; un identifiant court généré par le serveur suffit pour retrouver les données. L'application réunit une SPA Angular 22, une API Fastify, Drizzle et SQLite dans un service NixOS reproductible.", Stack: "Angular 22, Fastify, TypeScript, Drizzle ORM, SQLite, NixOS"},
			{Name: "jav", URL: "https://github.com/sachahjkl/jav", Description: "CLI écrite en Rust pour apporter à l'écosystème Java une expérience cohérente proche de celle de la CLI .NET. Elle détecte les projets Maven, Gradle ou Java simples et unifie les commandes de création, build, test, exécution, nettoyage, diagnostic et mise à jour. Dix modèles couvrent les usages courants, de la console à Spring, avec un flake Nix généré par défaut pour fournir un environnement reproductible.", Stack: "Rust, Java, Maven, Gradle, Nix, GitHub Actions"},
		},
		Catalog: []CareerGroup{
			{Title: "Applications et sites", Items: []string{"lanblaster.sacha.house", "froment.software", "chat.sacha.house", "wthhyb.sacha.house", "albumator", "clockin.sacha.house", "marketing.sacha.house", "button.sacha.house", "cool.sacha.house", "react-training.sacha.house"}},
			{Title: "Outils et systèmes", Items: []string{"nixconfig", "dotfiles", "jav", "dw", "MEGA_CLI", "subtitles-translater", "one_piece_dl_scan", "mrtg-autoinstall", "epicmousemover", "electrorustogram"}},
			{Title: "Expérimentations", Items: []string{"Achetétéper", "htmx.sacha.house", "Rust Testground", "Win32 Trainer", "Rudimentary File Explorer", "JS Canvas Speed Experiment", "odd_or_even", "prime", "Template Ts Gql Express", "chaussures-api", "pixels"}},
			{Title: "Projets académiques", Items: []string{"Portefeuille Ethereum Android en Kotlin", "Musées du monde en RDF/SPARQL et Symfony", "Prototype REST hypermédia contre GraphQL en Svelte", "Bibliothèque JSP", "services web dynamiques", "simulation de propagation virale", "emploi du temps web", "algorithmes de sac à dos", "messagerie Java", "Sudoku C#"}},
			{Title: "Thèmes, configurations et archives", Items: []string{"Grind Brother Grind", "hugo_theme_hjkl.it", "sachahjkl.gitlab.io", "kickstart.nvim", "wofi-arc-dark", "dwm", "st", "dotfiles_old", "basex_chocolatey", "kelio-rewrite", "wackssenger"}},
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
	profile.Title = "Software and systems engineer"
	profile.Summary = "Software and systems engineer specializing in the modernization of business applications and their development pipelines. My work spans .NET and web development, tooling, performance, and Linux operations, with a consistent focus on reliability and cycle time."
	profile.Nationality = "French"
	profile.AgeLabel = "years old"
	profile.ContactLabel = "Contact"
	profile.ExperienceLabel = "Experience"
	profile.EducationLabel = "Education"
	profile.SkillsLabel = "Skills"
	profile.ProjectsLabel = "Selected projects"
	profile.CatalogLabel = "Project catalog"
	profile.PublicationsLabel = "Publications"
	profile.LanguagesLabel = "Languages"
	profile.PrintLabel = "Print / PDF"
	profile.ResumeLabel = "Résumé"
	profile.CVLabel = "Full CV"
	profile.ProfileLabel = "Profile"
	profile.SelectedLabel = "Main achievements"
	profile.EnvironmentLabel = "Technical environment"
	profile.Experiences = []CareerExperience{
		{
			Period: "Since April 2025", Role: "Software engineer", Company: "Catamania", Context: "OGF assignment",
			Summary: "Assignment across several internal applications supporting order management and operations. Most work consists of feature development and defect correction with ASP.NET Core, Angular, and SQL Server. Key contributions include external service integration, agency-change redesign, and shared design of a cross-cutting permission system. The team works in Agile with Azure DevOps.",
			Details: []CareerDetail{
				{Title: "Organization", Text: "Development is distributed across several application teams, with scope changing as priorities evolve. The organization includes about fifteen developers and four to five product representatives. Technical design remains within the development teams; without a dedicated QA team, product representatives perform functional acceptance while developers own the required automated tests."},
				{Title: "External service integration", Text: "An order-item evaluation system was integrated through APIs supplied by external service providers. The implementation covers business rules, status tracking and display, error handling, and exchange logging, so processing remains understandable and actionable within the internal applications."},
				{Title: "Agency change", Text: "The workflow replaced a legacy mechanism limited to an unreliable city-code search. The new search uses Fuse.js to apply fuzzy matching across agency attributes, including city and address, and returns results suited to the business workflow."},
				{Title: "Application architecture", Text: "The suite exchanges data across applications through JSON-over-HTTP APIs, inter-application flows, and a service bus. Its architecture combines established CRUD operations with the progressive introduction of CQRS to separate read, write, and business processing responsibilities more clearly."},
				{Title: "Profiles and permissions", Text: "A major contribution involved the shared design of a cross-cutting system, now used in production instead of historical checks scattered across individual features. Permission calculation combines groups from Active Directory, database attributes tied to the user, and session information. These inputs are matched against hierarchical profile declarations, their permissions, and complementary dynamic rules. The result drives both conditional rendering in Angular and access control in the .NET APIs."},
				{Title: "Permission validation", Text: "The model is validated through numerous generated positive and negative cases derived from access conditions. Regular review with product owners ensured that the generalized system preserved the business rules covered by the previous implementation."},
				{Title: "Front-end modernization", Text: "The Angular 17 to Angular 21 migration was delivered end to end, including AST codemods for transformations missing from official tooling. More than 900 tests were moved from Jest to Vitest and parallelized, reducing runtime from about 20 minutes to 30 seconds."},
				{Title: "Performance and continuous integration", Text: "The same measurement-driven work reduced the front-end pipeline from 30 minutes to 5 or 6 minutes, and the back-end pipeline from 20 minutes to 7 minutes as part of a shared effort. Application profiling and removal of loading cascades reduced a complex page load from about five seconds to one second."},
				{Title: ".NET platform", Text: "The platform was consolidated through shared Directory.Build.props rules and dependency locking. Exploratory work with Nix and .NET 10 assessed future changes without disrupting production paths."},
			},
			Environment: "C#, .NET 7/8, ASP.NET Core, Angular 17–21, TypeScript, SQL Server, Azure App Service, Azure DevOps, Active Directory, Fuse.js, Jest, Vitest",
		},
		{
			Period: "January 2023 – March 2025", Role: "Software engineer", Company: "AViSTO", Context: "Alstom assignment",
			Summary: "Two-year Alstom assignment on tools for embedded railway system configuration. Work included maintenance of WinForms applications on .NET Framework, independent design of a production .NET 8 CLI, and preparation of several dozen projects for migration from NAnt to MSBuild.",
			Details: []CareerDetail{
				{Title: "Production CLI", Text: "Working from technical specifications that defined binary layouts, field sizes, and exchange rules, I independently designed and implemented the tool. It produces technical-data archives for selected train systems, validates XML documents against specialized schemas, checks data consistency, then encrypts and signs the resulting files. Typed results, diagnostics, and exit codes make failures actionable for both users and automated processing."},
				{Title: "Build-system migration", Text: "The legacy system was prepared for migration from NAnt to MSBuild across several dozen C# projects. The work went beyond script translation: it required analysis of the dependency graph, mitigation of cycle risks, revision of some project boundaries, and correct integration of code-generation modules into the Visual Studio build lifecycle."},
				{Title: "Automation and handover", Text: "Tools automated repetitive transformations while preserving explicit handling for project-specific behavior. Visual Studio and GitLab CI integration, together with target-architecture documentation, prepared the team to continue the migration."},
				{Title: "Quality", Text: "Changes to configuration and comparison tools were secured with NUnit unit and integration tests in an environment combining .NET Framework 4 and .NET 8."},
			},
			Environment: "C#, .NET Framework 4, .NET 8, WinForms, NUnit, XML Schema, encryption, signing, NAnt, MSBuild, Visual Studio, GitLab CI",
		},
		{
			Period: "September 2019 – June 2022", Role: "Information systems assistant, apprenticeship", Company: "AG2R La Mondiale",
			Summary: "Apprenticeship within the information-system mapping team. Designed and maintained a TypeScript framework progressively deployed across almost 50,000 pages, evolved C# and VBScript processing, and contributed to the MEGA HOPEX V2R1-to-V5 migration through production deployment.",
			Details: []CareerDetail{
				{Title: "Front-end redesign", Text: "Modernization led to a 25-module, 4,900-line TypeScript framework that redesigned almost 50,000 pages generated by the platform. Its architecture added state management, hooks, mounting on an existing DOM, and dynamic loading while preserving the existing XML, JSON, SOAP, and REST exchanges."},
				{Title: "Deployment and maintenance", Text: "Rolled out progressively during the apprenticeship, this layer replaced an old fixed-width interface. It restructured navigation and the views for business data, applications, and technologies, then added contextual links between previously isolated information. I remained its sole maintainer until leaving the company."},
				{Title: "Build and integration", Text: "The supporting toolchain used Webpack 5, Babel, TypeScript, and Sass. PowerShell scripts then standardized builds and deployments across environments. Extraction, import, and API processing continued to evolve in VBScript and C#."},
				{Title: "MEGA HOPEX migration", Text: "The V2R1 to V5 migration covered customizations, dependencies, scripts, and operational infrastructure including IIS, SAML2 SSO, backups, and SQL restoration. The work combined implementation, scoping, operational preparation, and handover documentation through production deployment of the new version."},
			},
			Environment: "TypeScript, Webpack 5, Babel, Sass, PowerShell, C#, VBScript, XML, JSON, SOAP, REST, MEGA HOPEX, IIS, SAML2, SQL Server",
		},
		{Period: "June – October 2022", Role: "Product Owner", Company: "AG2R La Mondiale", FullOnly: true, Summary: "Temporary role focused on the inventory and mapping of information-system technologies, servers, and software, extending the work performed on the HOPEX platform."},
		{Period: "April – August 2019", Role: "Systems administration intern", Company: "Italic", Summary: "Administered 5 to 10 Linux VPS instances hosting customer websites. Bash automation covered configuration, backups, deployments, and monitoring for the LAMP infrastructure.", Details: []CareerDetail{{Title: "Automation and operations", Text: "Bash scripts automated server configuration, backups, deployments, and monitoring. Operations relied on Apache, PHP, MySQL or MariaDB, SSH, and rsync. Additional research explored Ruby-based automation of EBICS banking statements."}}, Environment: "Linux, Bash, Apache, PHP, MySQL/MariaDB, SSH, rsync, OVH, Ruby, EBICS"},
	}
	profile.Education = []CareerEducation{
		{Period: "2019 – 2022", Degree: "Engineering degree in computer science, information systems", School: "Conservatoire national des arts et métiers", Description: "My thesis covered obsolescence management, project scoping, change management, and the production migration to MEGA HOPEX V5. I acted as joint technical project lead."},
		{Period: "2020 – 2021", Degree: "REST hypermedia and GraphQL study", School: "Conservatoire national des arts et métiers", Description: "I compared both API models and independently built a Svelte prototype in three and a half days to assess their constraints and impact on the web client.", FullOnly: true},
		{Period: "2019 – 2020", Degree: "Information-system mapping platform modernization", School: "Conservatoire national des arts et métiers", Description: "The first activity report documented the AG2R platform modernization and development work in C# with Graphviz, JavaScript, and VBScript.", FullOnly: true},
		{Period: "2017 – 2019", Degree: "Two-year university degree in computer science", School: "IUT Paris Descartes", Description: "The course covered software, web, data, systems, and networks. I participated in Nuit de l'Info 2018."},
	}
	profile.Skills = []CareerGroup{
		{Title: "Application development", Items: []string{"I work primarily with C#, .NET Framework, .NET 7/8, ASP.NET Core, WinForms, TypeScript, Angular, and Go. I design business web applications, desktop applications, CLIs, and integration tools. Svelte 5 and SvelteKit complement this work in personal projects."}},
		{Title: "Testing and performance", Items: []string{"I use Vitest, Jest, and NUnit for unit and integration testing. I profile applications and build chains before changing execution times, data access, or parallelism."}},
		{Title: "Data, build, and delivery", Items: []string{"I work with SQL Server, SQLite, XML, JSON, SOAP, REST, and GraphQL. My delivery chains use Azure DevOps, GitLab CI, GitHub Actions, MSBuild, NAnt, Webpack 5, Babel, PowerShell, Nix, Docker, and Azure App Service."}},
		{Title: "Systems", Items: []string{"I administer Linux and NixOS systems with systemd, containers, virtualization, Apache, backups, and monitoring. Bash, SSH, and rsync support their operation."}},
		{Title: "Professional practices", Items: []string{"I work in Agile teams with product, business, and technical stakeholders. I write specifications, architecture documents, interface descriptions, and operating procedures. My experience also includes project scoping, change management, and technical presentations."}},
	}
	profile.ResumeSkills = []string{
		"Application development: C#, .NET, Angular, TypeScript, Go, and SQL for web, desktop, and command-line applications.",
		"Quality and delivery: automated tests, profiling, Azure DevOps, GitLab CI, MSBuild, Webpack, Docker, Linux, and NixOS.",
		"Professional practices: Agile teamwork, product and business collaboration, technical documentation, project scoping, and change management.",
	}
	profile.Projects = []CareerProject{
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
		{Title: "Themes, configurations, and archives", Items: profile.Catalog[4].Items},
	}
	profile.Publications[0].Date = "November 2025"
	profile.Publications[1].Date = "November 2025"
	profile.Publications[2].Date = "October 2025"
	profile.Publications[3].Date = "March 2023"
	profile.Languages = []string{"French: native", "English: bilingual professional and technical proficiency"}
	return profile
}
