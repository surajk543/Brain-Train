// Worker "sungamestudio-app-ads", route sungamestudio.com/app-ads.txt (zone sungamestudio.com): serves AdMob's
// app-ads.txt line for the Tile Park apps (publisher pub-6766349950907943), so AdMob can verify them. Every other
// path on sungamestudio.com still goes to the website (nginx on game-server-01). Same line as website/app-ads.txt.
const APP_ADS = 'google.com, pub-6766349950907943, DIRECT, f08c47fec0942fa0\n';

export default {
  async fetch() {
    return new Response(APP_ADS, {
      headers: {'content-type': 'text/plain; charset=utf-8', 'cache-control': 'public, max-age=3600'},
    });
  },
};
