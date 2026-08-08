# Projet Ecole (Vapel)

Script Roblox (`Vapel.lua`) execute via un executeur cote client. Le fichier
entier est charge/compile comme un seul script Luau.

## Contrainte critique : limite Luau de 200 registres locaux

Luau limite chaque **fonction** a 200 registres locaux actifs simultanement.
`Vapel.lua` est ecrit comme un unique chunk de script (pas de decoupage en
modules), donc **tout le fichier compte comme une seule fonction** vis-a-vis
de cette limite. Un local ne libere son registre que quand le bloc lexical
qui le contient (`do...end`, `if`, `for`, `function`...) se termine.

Le fichier a deja depasse cette limite plusieurs fois en ajoutant des
fonctionnalites (ESP, pages Skin, Auto...) - voir les commits "Collapse
Skin-page block locals into a table to fix Luau 200-register limit" et
similaires. L'erreur ressemble a :

```
COMPILE ERROR: :<ligne>: Out of local registers when trying to allocate <Nom>: exceeded limit 200
```

**A chaque fois que du code est ajoute ou modifie dans `Vapel.lua`** (nouvelle
section UI, nouvelle feature, nouvelle variable d'etat...), appliquer ces
regles :

- Isoler toute nouvelle section/feature qui declare des locals qui ne sont
  pas reutilises en dehors de son perimetre immediat (typiquement un
  `local XSection = addSection(...)` suivi de quelques `addXRow(XSection, ...)`)
  dans son propre `do ... end`. Ca libere ses registres a la fin du bloc
  plutot que de les garder ouverts jusqu'a la fin du fichier.
- Des qu'une section a besoin de PLUSIEURS locals internes (helpers, modules
  `require`d, tables de lookup) pour construire UNE closure qui sera utilisee
  plus bas (ex: le handler d'un bouton), forward-declarer cette closure
  (`local maFonction`) puis la construire a l'interieur d'un `do ... end`
  imbrique qui capture tous les helpers comme upvalues et se referme aussitot
  apres (`maFonction = function(...) ... end`). Seule `maFonction` doit
  survivre en dehors ; tout le reste (le module require, les fonctions de
  calcul intermediaires...) libere son registre a la fermeture du bloc. Meme
  pattern que `setAfkAgeUp`/`setPanicTeleport` (haut du fichier) et que les
  sections "Vendre Tout"/"Spectate Leaderboard" (bloc FEATURE_CONTROLS) - a
  appliquer par defaut des qu'une section depasse ~4-5 locals internes, pas
  seulement en reaction a une erreur de compilation.
- Ne jamais creer une variable locale par controle UI (toggle/slider/dropdown) :
  ecrire directement dans la table partagee `FEATURE_CONTROLS` (voir le bloc
  `local applyFeatureSettings do ... end` dans `Vapel.lua`), comme c'est deja
  fait partout dans ce fichier.
- Preferer regrouper des variables d'etat apparentees dans une table plutot
  que des locals separes quand elles n'ont pas besoin d'etre individuellement
  nommees (meme pattern que la page Skin, deja refactoree pour cette raison).
- Si l'erreur revient malgre ce wrapping sur le nouveau code, chercher
  d'autres blocs "a plat" plus haut dans le fichier (`local X = ...` non
  imbriques dans un `do...end` qui se referme) a regrouper - le total cumule
  sur tout le fichier compte, pas seulement le code ajoute en dernier.
- Il n'existe pas de linter/compilateur Luau installe dans cet environnement
  pour verifier ca avant de pousser : la seule verification reelle se fait en
  executant le script dans le jeu. Etre generalement large dans l'usage des
  registres (marge de securite) plutot que de viser l'exacte limite.

Une note detaillee equivalente est dupliquee en tete de `Vapel.lua` lui-meme.

## Contexte du projet

Script "cheat" client (ESP, fly, noclip, teleport, auto-sell...) pour un jeu
Roblox, construit avec un executeur (`request`, `listfiles`, `setclipboard`,
etc. - fonctions non standard disponibles uniquement via un executeur).
