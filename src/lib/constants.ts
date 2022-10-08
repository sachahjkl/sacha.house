import { capitalize } from './utils';

export const MOI = {
	nom: 'froment',
	prenom: 'sacha',
	dateNaissance: new Date('25/05/1999'),
	github: new URL('https://github.com/sachahjkl'),
	gitlab: new URL('https://gitlab.com/sachahjkl'),
	linkedin: new URL('https://www.linkedin.com/in/sachafroment/')
};

export const SITE_TITLE = `${capitalize(MOI.prenom.toLowerCase())} ${MOI.nom.toUpperCase()} `;
