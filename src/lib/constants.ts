import { capitalize } from './utils';


export const MOI = {
	nom: 'froment',
	prenom: 'sacha',
	username: 'sachahjkl',
	dateNaissance: new Date('1999-05-25T00:00:00+02:00'),
	placeOfLiving: 'Paris',
	github: new URL('https://github.com/sachahjkl'),
	gitlab: new URL('https://gitlab.com/sachahjkl'),
	linkedin: new URL('https://www.linkedin.com/in/sachafroment/'),
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
