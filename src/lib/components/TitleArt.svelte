<script>
	import { asciiArt } from '$lib/ascii_art';
</script>
<!-- make the pre relative to the width of the screen -->

<pre class="inline-block text-transparent bg-clip-text text-[1.4vw]">
		{asciiArt}
	</pre>

<style>
    pre {
        background-image: url("/gifs/fire.gif");
        background-size: cover;
    }
</style>

