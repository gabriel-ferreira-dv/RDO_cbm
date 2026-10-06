// Converte os tiles de overlay de PNG para WebP (preservando transparência).
//
// Os tiles são fotos aéreas com traçado do CAD por cima: PNG é péssimo para
// conteúdo fotográfico (~725 MB no total), enquanto WebP com alfa entrega o
// mesmo resultado visual em ~15% do tamanho, e o Flutter lê WebP nativamente.
//
// Uso (precisa de `npm install sharp` nesta pasta):
//   node tool/converter_tiles_webp.js            → converte, mantendo os PNGs
//   node tool/converter_tiles_webp.js --mover    → converte e move os PNGs
//                                                  para _tiles_png_backup/
//
// Depois de mover os PNGs, só os .webp entram no APK. Para voltar atrás,
// basta devolver os PNGs de _tiles_png_backup/ e reverter a extensão usada
// em lib/features/mapa/presentation/pages/map_page.dart.
const sharp = require('sharp');
const fs = require('fs');
const path = require('path');

const QUALIDADE = 100; // -80% de tamanho, sem diferença visível em 1:1
const CONCORRENCIA = 8;

const RAIZ = path.join(__dirname, '..');
const PASTAS = ['assets/d2M'];
const BACKUP = path.join(RAIZ, '_tiles_png_backup');
const mover = process.argv.includes('--mover');

async function emLotes(itens, tamanho, tarefa) {
  for (let i = 0; i < itens.length; i += tamanho) {
    await Promise.all(itens.slice(i, i + tamanho).map(tarefa));
  }
}

(async () => {
  for (const pastaRel of PASTAS) {
    const pasta = path.join(RAIZ, pastaRel);
    if (!fs.existsSync(pasta)) {
      console.log(`(pulando ${pastaRel}: não existe)`);
      continue;
    }
    const pngs = fs.readdirSync(pasta).filter((f) => f.toLowerCase().endsWith('.png'));
    let bytesAntes = 0;
    let bytesDepois = 0;

    await emLotes(pngs, CONCORRENCIA, async (arquivo) => {
      const origem = path.join(pasta, arquivo);
      const destino = path.join(pasta, arquivo.replace(/\.png$/i, '.webp'));
      bytesAntes += fs.statSync(origem).size;
      await sharp(origem)
        .webp({ quality: QUALIDADE, alphaQuality: 100 })
        .toFile(destino);
      bytesDepois += fs.statSync(destino).size;
    });

    const mb = (b) => (b / 1024 / 1024).toFixed(1);
    const reducao = bytesAntes ? ((1 - bytesDepois / bytesAntes) * 100).toFixed(1) : '0';
    console.log(
      `${pastaRel}: ${pngs.length} tiles  ${mb(bytesAntes)} MB -> ${mb(bytesDepois)} MB  (-${reducao}%)`
    );

    if (mover) {
      const destinoBackup = path.join(BACKUP, path.basename(pastaRel));
      fs.mkdirSync(destinoBackup, { recursive: true });
      for (const arquivo of pngs) {
        fs.renameSync(path.join(pasta, arquivo), path.join(destinoBackup, arquivo));
      }
      console.log(`  PNGs movidos para _tiles_png_backup/${path.basename(pastaRel)}`);
    }
  }
})();
