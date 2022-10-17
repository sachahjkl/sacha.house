import { capitalize } from './utils';

export const MOI = {
	nom: 'froment',
	prenom: 'sacha',
	username: 'sachahjkl',
	/** @type {import("./interfaces/Person").Config} */
	gender: 'male',
	dateNaissance: new Date('1999-05-25T00:00:00+02:00'),
	placeOfLiving: 'Paris',
	github: new URL('https://github.com/sachahjkl'),
	gitlab: new URL('https://gitlab.com/sachahjkl'),
	linkedin: new URL('https://www.linkedin.com/in/sachafroment/'),
	mail: 'sacha@sacha.house',
	curriculumVitae: new URL(
		'https://mega.nz/file/7oF2SBwR#LFdx6o9LnntuK4Z0LjHegn5a7PRiXgZ1SFw0R_qmNQk'
	),
	ethAddress: '0xDfB091f812ea27Ca58e8f556B252f245660cba87',
	moneroAdress:
		'49ETBPrD54iCKeecWjPt2hfjciSRgptXzJc29Hd8FS97AQHzThdoxE1aE4NigAf8xYDxok1iaaGKD8a6EmUwUgkgTstDaFJ',
	links: {
		dotfiles: new URL('https://gitlab.com/sachahjkl/dotfiles'),
		hayekfr: new URL('https://ilone.hayek.fr/'),
		hayekfrRepo: new URL('https://gitlab.com/bonzybuddy/bonzybuddy.gitlab.io')
	}
};

export const PRETTY_PRENOM = capitalize(MOI.prenom.toLowerCase());
export const PRETTY_NOM = MOI.nom.toUpperCase();
export const SITE_TITLE = `${PRETTY_PRENOM} ${PRETTY_NOM}`;

export const countAPIConfig = {
	namespace: 'sacha.house',
	key: 'visites'
};
