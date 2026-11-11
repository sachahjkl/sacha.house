Ce billet annonçait la refonte de 2022. La pile SvelteKit, GraphQL et Netlify décrite à l'origine n'est plus celle qui sert le site aujourd'hui.

La version actuelle repose sur un serveur écrit en [Odin](https://odin-lang.org/), des modèles HTML générés avec Temple, [Tailwind CSS](https://tailwindcss.com/) pour les styles et [Nix](https://nixos.org/) pour des builds et des déploiements reproductibles. Le site reste volontairement sobre : le HTML rendu côté serveur assure l'essentiel, et le JavaScript est réservé aux interfaces qui en ont besoin.

Cette évolution poursuit le même objectif qu'au départ : garder un espace personnel rapide, lisible et facile à faire évoluer.
