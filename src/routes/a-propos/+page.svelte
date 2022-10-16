<script>
	import { MOI, SITE_TITLE } from '$lib/constants';
	import { capitalize } from '$lib/utils';

	import picSrc from '$lib/assets/me.jpg';
	import CopyableValue from '$lib/components/CopyableValue.svelte';
</script>

<svelte:head>
	<title>à propos / {SITE_TITLE}</title>
</svelte:head>

<article class="prose">
	<h1 class="">à propos</h1>
	<section>
		<div class="avatar block mx-auto">
			<div class="pic">
				<img class="me" src={picSrc} alt="Moi" />
			</div>
		</div>

		<p>
			Je m'appelle <b>{capitalize(MOI.prenom)} {capitalize(MOI.nom)}</b>, j'ai
			<em>{new Date().getFullYear() - MOI.dateNaissance.getFullYear()} ans</em>
			j'habite à <em>{MOI.placeOfLiving}</em>.
		</p>
		<p>Je suis ingénieur en informatique. J'aspire à produire du travail simple et de qualité</p>

		<p>
			N’hésitez pas à <a href="mailto:{MOI.mail}">m’envoyer un mail</a> à propos de ce que vous pensez
			de ce site ou tout autre sujet qui pourrait m’intéresser (travail, discussion, projet, ...).
		</p>
	</section>
	<div class="divider" />
	<section>
		<h2 id="détails-professionnels"> Détails professionels </h2>
		<p>
			Lorem ipsum dolor sit amet, consectetur adipisicing elit. Porro magni neque commodi fugit
			tempore unde velit laudantium illum deserunt modi beatae iste amet soluta quam consectetur
			obcaecati recusandae, reiciendis maxime!
		</p>
	</section>
	<div class="divider" />
	<section>
		<h2>Contact</h2>
		<p>Voici, en vrac, une liste d'information de contact me concernant :</p>
		<ul>
			<li>Mail : <CopyableValue value={MOI.mail} /></li>
			<li>Adresse Ethereum : <CopyableValue value={MOI.ethAddress} /></li>
			<li>
				Adresse Monero : <CopyableValue value={MOI.moneroAdress} />
			</li>
			<li>
				Profil linkedinProfile : <a href={MOI.linkedin.toString()}>{MOI.linkedin.toString()}</a>
			</li>
			<li>
				Profil GitHub : <a href={MOI.github.toString()}>{MOI.github.toString()}</a>
			</li>
			<li>
				Profil GitLab : <a href={MOI.gitlab.toString()}>{MOI.gitlab.toString()}</a>
			</li>
		</ul>
	</section>
</article>

<style lang="postcss">
	.pic {
		@apply w-80 mx-auto rounded-full ring-4 hover:ring-8
		hover:ring-secondary hover:scale-105 active:ring-success active:scale-95
		transition-all ring-primary ring-offset-base-100 ring-offset-2;
	}
	article {
		@apply mx-auto;
	}
	.me {
		@apply m-0;
	}
	a {
		@apply hover:scale-105 transition-all;
	}

</style>
