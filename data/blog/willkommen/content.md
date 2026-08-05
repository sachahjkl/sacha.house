Je suis fier de vous présenter la nouvelle version de mon site, entièrement réécrite de zéro. Je suis passé d'une stack technologique purement statique à un stack entièrement dynamique et exploitant les dernières nouveautés. Mon ancien site est toujours disponible à [https://old.sacha.house](https://old.sacha.house "L'ancienne version de mon site") .

L'ancienne stack comprenait :

\- [Hugo](https://gohugo.io/ "https://gohugo.io/") (générateur de site statique).

\- [CSS](https://developer.mozilla.org/fr/docs/Web/CSS "https://developer.mozilla.org/fr/docs/Web/CSS") construit à la main.

\- [JavaScript](https://developer.mozilla.org/fr/docs/Web/JavaScript "https://developer.mozilla.org/fr/docs/Web/JavaScript") écrit à la main.

\- [Gitlab Pages](https://docs.gitlab.com/ee/user/project/pages/ "https://docs.gitlab.com/ee/user/project/pages/") + [Gitlab CI/CD](https://docs.gitlab.com/ee/ci/ "https://docs.gitlab.com/ee/ci/") pour l'hébergement et le déploiement automatique.

Ma nouvelle stack est à l'opposé polaire de l'ancienne en terme d'approche de conception :

\- [SvelteKit](https://kit.svelte.dev/ "Meilleur framework") (framework web full stack bleeding edge).

\- [Svelte](https://svelte.dev/ "Meilleure bibliothèque UI") bibliothèque/compilateur de composants UI web.

\- [GraphQL](https://graphql.org/ "https://graphql.org/") pour les appels vers les différentes API externes (Github, Gitlab, ...) avec [graphql-request](https://github.com/prisma-labs/graphql-request "https://github.com/prisma-labs/graphql-request").

\- [Netlify](https://www.netlify.com/ "https://www.netlify.com/") pour le déploiement du site web. Utilise les nouvelles [Edge Functions](https://docs.netlify.com/edge-functions/overview/ "https://docs.netlify.com/edge-functions/overview/") qui permettent de drastiquement améliorer la performance globale du site.

\- [Typescript](https://www.typescriptlang.org/ "https://www.typescriptlang.org/") pour éviter d'écrire du code qui casse à chaque ligne.

\- [TailwindCSS](https://tailwindcss.com/ "https://tailwindcss.com/"), framework CSS utility-first (sorte de CSS raccourci).

\- [DaisyUI](https://daisyui.com/ "https://daisyui.com/"), une bibliothèque de composant reposant purement conçue avec TailwindCSS.

N'hésitez pas à m'envoyer un mail si vous avez des remarques !
