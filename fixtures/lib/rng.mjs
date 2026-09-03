// Générateur pseudo-aléatoire à graine : mulberry32.
//
// Pourquoi pas Math.random : le jeu de données doit être reproductible à
// l'identique, sinon le fichier de résultats attendus ne vaut rien. Deux
// exécutions avec la même graine doivent produire des CSV identiques au
// caractère près.
//
// Pourquoi pas crypto : on ne cherche pas de l'imprévisible, on cherche du
// varié et du rejouable. mulberry32 tient en dix lignes et n'a aucune
// dépendance, ce qui est la règle du dépôt pour tout ce qui est exécutable
// (cf. tests/apex_page_test.mjs).

export function makeRng (seed) {
   let a = seed >>> 0;

   const next = () => {
      a = (a + 0x6d2b79f5) >>> 0;
      let t = a;
      t = Math.imul(t ^ (t >>> 15), t | 1);
      t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
      return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
   };

   return {
      // Flottant dans [0,1[
      next,
      // Entier dans [min,max] inclus des deux côtés
      int: (min, max) => min + Math.floor(next() * (max - min + 1)),
      // Un élément d'un tableau
      pick: (arr) => arr[Math.floor(next() * arr.length)],
      // Vrai avec la probabilité p
      chance: (p) => next() < p,
      // Mélange en place (Fisher-Yates), et rend le tableau
      shuffle: (arr) => {
         for (let i = arr.length - 1; i > 0; i--) {
            const j = Math.floor(next() * (i + 1));
            [arr[i], arr[j]] = [arr[j], arr[i]];
         }
         return arr;
      },
      // n éléments distincts, pris au hasard, sans modifier la source
      sample: (arr, n) => {
         const copy = arr.slice();
         for (let i = copy.length - 1; i > 0; i--) {
            const j = Math.floor(next() * (i + 1));
            [copy[i], copy[j]] = [copy[j], copy[i]];
         }
         return copy.slice(0, Math.min(n, copy.length));
      }
   };
}
