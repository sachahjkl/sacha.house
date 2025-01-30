// eslint-disable-next-line @typescript-eslint/no-unused-vars
import type { Gender } from './interfaces/Person';
import { capitalize } from './utils';

export const MOI = {
	nom: 'froment',
	prenom: 'sacha',
	username: 'sachahjkl',
	/** @type {Gender} */
	gender: '',
	dateNaissance: new Date('1999-05-25T00:00:00+02:00'),
	placeOfLiving: 'le Mans',
	github: new URL('https://github.com/sachahjkl'),
	gitlab: new URL('https://gitlab.com/sachahjkl'),
	linkedin: new URL('https://www.linkedin.com/in/sachafroment/'),
	homepage: new URL('https://sacha.house'),
	mail: 'sacha@sacha.house',
	curriculumVitae: '/cv.html',
	ethAddress: '0xDfB091f812ea27Ca58e8f556B252f245660cba87',
	gpgPrint: '21D64EBC463D12DFE373AE4F1EFE264F809A2118',
	moneroAdress:
		'49ETBPrD54iCKeecWjPt2hfjciSRgptXzJc29Hd8FS97AQHzThdoxE1aE4NigAf8xYDxok1iaaGKD8a6EmUwUgkgTstDaFJ',
	links: {
		dotfiles: new URL('https://gitlab.com/sachahjkl/dotfiles'),
		hayekfr: new URL('https://ilone.hayek.fr/'),
		hayekfrRepo: new URL('https://gitlab.com/bonzybuddy/bonzybuddy.gitlab.io')
	},
	get prettyPrenom() {
		return capitalize(this.prenom.toLowerCase());
	},
	get prettyNom() {
		return capitalize(this.nom.toLowerCase());
	},
	get siteTitle() {
		return `${this.prettyPrenom} ${this.prettyNom}`;
	}
};
