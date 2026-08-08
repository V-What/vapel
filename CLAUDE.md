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
- Un `do ... end` imbrique ne libere des registres QUE pour ce qui est
  declare AVANT lui et se referme avant la suite - il ne fait rien pour des
  helpers qui sont freres entre eux dans le MEME bloc (ils restent tous
  ouverts simultanement jusqu'a la fin du bloc, meme nombreux). Deux cas
  concrets deja rencontres dans ce fichier :
  - Cas "build puis utilise" (une closure a construire, dont la construction
    a besoin de plusieurs helpers qui ne servent plus apres) : forward-declarer
    la closure finale (`local maFonction`), la construire a l'interieur d'un
    `do ... end` imbrique qui capture les helpers comme upvalues et se
    referme aussitot apres (`maFonction = function(...) ... end`). Seule
    `maFonction` doit survivre en dehors. Exemples : `setAfkAgeUp`/
    `setPanicTeleport` (haut du fichier), section "Vendre Tout".
  - Cas "plusieurs helpers qui doivent TOUS rester actifs en meme temps"
    (ex: une feature avec plusieurs fonctions qui s'appellent entre elles et
    un etat partage, genre hook + callback + scheduler) : le `do...end` seul
    ne suffit pas puisqu'aucun des helpers ne peut se fermer avant les
    autres. Regrouper alors l'etat dans UNE table (`local state = { ... }`)
    et les fonctions en methodes d'UNE autre table plutot qu'en
    `local function` separees (`function M.foo(...) ... end` est une
    affectation de champ, pas un nouveau local - donc gratuit en registres).
    Exemple concret : section "Auto Spectate au clic" (Spectate Leaderboard)
    - 8 locals a plat (3 d'etat + 5 fonctions) depassaient a eux seuls la
    limite malgre le `do...end` ; les regrouper dans `state` + `M` a fait
    tomber le cout de ce bloc a 2 registres.
  - Par defaut, des qu'une section a plus de ~4-5 locals internes (helpers ou
    etat), partir directement sur le pattern table(s) plutot que d'essayer le
    `do...end` seul en premier - plus sur et evite un aller-retour.
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
