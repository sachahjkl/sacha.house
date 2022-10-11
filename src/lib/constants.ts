import { capitalize } from './utils';

// à renouveller de temps en temps avec https://nubela.co/proxycurl/api/v2/linkedin
export const linkedinProfile = {
	public_identifier: 'sachafroment',
	profile_pic_url:
		'https://media-exp1.licdn.com/dms/image/C4E03AQHuhn2SR4Wmmg/profile-displayphoto-shrink_800_800/0/1651914555473?e=2147483647&v=beta&t=9xXyrPMeXB5nvv1WY0gjjKbnOCu4OteKRLL5IZZ9vKM',
	background_cover_image_url:
		'https://media-exp1.licdn.com/dms/image/C5616AQFzfsIGPp0CVg/profile-displaybackgroundimage-shrink_200_800/0/1527102709560?e=2147483647&v=beta&t=T-3UV-RyjM9sF5CuOMoXbWG12rqb1wI_4RAw3UAZEgk',
	first_name: 'Sacha',
	last_name: 'Froment',
	full_name: 'Sacha Froment',
	occupation: 'Product Owner Caroline/UDI at AG2R LA MONDIALE',
	headline: "Ingénieur en Informatique spécialisé dans les systèmes d'information",
	summary:
		"Polyvalent et efficace, je m'adapte à tout les cadres de travail. \n\nJe suis compétent dans de nombreux domaine de l'informatique et fais preuve d'une insatiable curiosité. \nJ'aspire à produire des projets rigoureusement conçus, architecturalement solide et pouvant être facilement maintenus.\n\nJe concentre actuellement mes efforts sur la réalisation de projets portants sur des technologies du web : ASP.NET Core (Blazor MVC, ASP.NET, etc), Svelte et React. Je m'instruis néanmoins sur toutes les technologies du marché.\n\nJ'élargis continuellement mon périmètre de connaissances sur toujours plus d'outils, langages et technologies. Je lis quotidiennement des blogs et fils d'actualités (hacker news, lobste.rs, devurls.com, etc) afin de me tenir au courant de l'état de l'art du marché.\n\nJe produis régulièrement des projets personnels afin de m'approprier tout ces outils que je découvre et de devenir adepte d'un maximum de pratiques et d'outils de développement logiciel (la liste de technologie que j'étudie serait trop longue pour en parler ;).",
	country: 'FR',
	country_full_name: 'France',
	city: 'Paris et périphérie',
	state: null,
	experiences: [
		{
			starts_at: {
				day: 1,
				month: 6,
				year: 2022
			},
			ends_at: {
				day: 31,
				month: 10,
				year: 2022
			},
			company: 'AG2R LA MONDIALE',
			company_linkedin_profile_url: 'https://fr.linkedin.com/company/ag2r-la-mondiale',
			title: 'Product Owner Caroline/UDI',
			description: "inventaire et cartographie des technologies, serveurs et logiciels du SI d'ALM",
			location: 'Ville de Paris, Île-de-France, France',
			logo_url:
				'https://media-exp1.licdn.com/dms/image/C560BAQHl1RvG-jIR2Q/company-logo_100_100/0/1596178960924?e=2147483647&v=beta&t=APUCOnNQ4Arq91_TVkWBMajiuda5-rQQv5l451tqvLY'
		},
		{
			starts_at: {
				day: 1,
				month: 9,
				year: 2019
			},
			ends_at: {
				day: 30,
				month: 9,
				year: 2022
			},
			company: 'AG2R LA MONDIALE',
			company_linkedin_profile_url: 'https://fr.linkedin.com/company/ag2r-la-mondiale',
			title: 'Assistant SI',
			description: null,
			location: 'Malakoff',
			logo_url:
				'https://media-exp1.licdn.com/dms/image/C560BAQHl1RvG-jIR2Q/company-logo_100_100/0/1596178960924?e=2147483647&v=beta&t=APUCOnNQ4Arq91_TVkWBMajiuda5-rQQv5l451tqvLY'
		},
		{
			starts_at: {
				day: 1,
				month: 4,
				year: 2019
			},
			ends_at: {
				day: 31,
				month: 7,
				year: 2019
			},
			company: 'ITALIC (Coding Forward)',
			company_linkedin_profile_url: 'https://fr.linkedin.com/company/eurl-italic',
			title: 'Développeur',
			description: null,
			location: 'Région de Paris, France',
			logo_url:
				'https://media-exp1.licdn.com/dms/image/C4D0BAQE75ORc_UKJjg/company-logo_100_100/0/1519909555242?e=2147483647&v=beta&t=xUvo5wsldv-GemU1M_421yQ7X5Iqd39pOdVDXZRbRcw'
		}
	],
	education: [
		{
			starts_at: {
				day: 1,
				month: 1,
				year: 2019
			},
			ends_at: {
				day: 31,
				month: 12,
				year: 2022
			},
			field_of_study: 'Informatique',
			degree_name: "Diplôme d'ingénieur",
			school: 'Conservatoire National des Arts et Métiers',
			school_linkedin_profile_url:
				'https://fr.linkedin.com/school/conservatoire-national-des-arts-et-m%C3%A9tiers/',
			description: "Ingénieur en informatique, spécialisé dans les systèmes d'information",
			logo_url:
				'https://media-exp1.licdn.com/dms/image/C4D0BAQGRQuv1v-KRxQ/company-logo_100_100/0/1604394648285?e=2147483647&v=beta&t=z4YApZd5-kc0PpOd5-PNm-GClfrgUPIFV2dVSa68LDc'
		},
		{
			starts_at: {
				day: 1,
				month: 1,
				year: 2017
			},
			ends_at: {
				day: 31,
				month: 12,
				year: 2019
			},
			field_of_study: 'Informatique',
			degree_name: 'DUT',
			school: 'IUT Paris Descartes',
			school_linkedin_profile_url: 'https://fr.linkedin.com/school/iut-paris-rives-de-seine/',
			description: null,
			logo_url:
				'https://media-exp1.licdn.com/dms/image/C4E0BAQGtVY4A24ML1g/company-logo_100_100/0/1653985819815?e=2147483647&v=beta&t=KpFCV2X45chGEvbHYnduuT02n1SbxjsvQIO5UxGT7s0'
		}
	],
	languages: [],
	accomplishment_organisations: [],
	accomplishment_publications: [],
	accomplishment_honors_awards: [],
	accomplishment_patents: [],
	accomplishment_courses: [],
	accomplishment_projects: [],
	accomplishment_test_scores: [],
	volunteer_work: [],
	certifications: [],
	connections: 172,
	people_also_viewed: [],
	recommendations: [],
	activities: [
		{
			title: 'Suis-je le seul à être fatigué des poseurs sur ce site ?',
			link: 'https://fr.linkedin.com/posts/sachafroment_suis-je-le-seul-%C3%A0-%C3%AAtre-fatigu%C3%A9-des-poseurs-activity-6965641174896230403-PqVi',
			activity_status: 'Publié par Sacha Froment'
		},
		{
			title: "⚙️⚙️⚙️ réflexion en cours ⚙️⚙️⚙️Résultat : si c'est vrai, c'est très grave !",
			link: 'https://fr.linkedin.com/posts/sachafroment_r%C3%A9flexion-en-cours-r%C3%A9sultat-activity-6965640601950154752-bh5r',
			activity_status: 'Partagé par Sacha Froment'
		},
		{
			title:
				'🍯 Tentez de gagner votre miel ;) 🍯 Nous sommes une association loi 1901 à but non lucratif et nous voulons faire connaître nos actions auprès du…',
			link: 'https://fr.linkedin.com/posts/la-maison-des-abeilles-heureuses_apiculture-biodiversit%C3%A9-rse-activity-6958692302173134848-FPM_',
			activity_status: 'Aimé par Sacha Froment'
		}
	],
	similarly_named_profiles: [
		{
			name: 'Sacha FROMENT',
			link: 'https://fr.linkedin.com/in/sacha-froment',
			summary: 'senior backend developer at Ortto',
			location: 'France'
		},
		{
			name: 'Sacha FROMENT',
			link: 'https://fr.linkedin.com/in/sacha-froment-715241b5',
			summary: 'Responsable des activités',
			location: 'Nîmes'
		}
	],
	articles: [],
	groups: []
};

export const MOI = {
	nom: 'froment',
	prenom: 'sacha',
	username: 'sachahjkl',
	dateNaissance: new Date('1999-05-25T00:00:00+02:00'),
	placeOfLiving: 'Paris',
	github: new URL('https://github.com/sachahjkl'),
	gitlab: new URL('https://gitlab.com/sachahjkl'),
	linkedin: new URL('https://www.linkedin.com/in/sachafroment/'),
	linkedinProfile,
	mail: 'sacha@sacha.house',
	ethAddress: '0xDfB091f812ea27Ca58e8f556B252f245660cba87',
	moneroAdress:
		'49ETBPrD54iCKeecWjPt2hfjciSRgptXzJc29Hd8FS97AQHzThdoxE1aE4NigAf8xYDxok1iaaGKD8a6EmUwUgkgTstDaFJ',
	links: {
		dotfiles: new URL('https://gitlab.com/sachahjkl/dotfiles'),
		hayekfr: new URL('https://ilone.hayek.fr/'),
		hayekfrRepo: new URL('https://gitlab.com/bonzybuddy/bonzybuddy.gitlab.io')
	}
};

export const SITE_TITLE = `${capitalize(MOI.prenom.toLowerCase())} ${MOI.nom.toUpperCase()} `;

export const countAPIConfig = {
	namespace: 'sacha.house',
	key: 'visites'
};
