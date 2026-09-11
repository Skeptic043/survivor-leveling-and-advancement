# Survivor Leveling & Advancement [B42]

Améliorez vos compétences, gagnez des points et dépensez-les dans celles de votre choix. SLA ajoute un niveau de survivant et des points d'avancement au panneau des compétences, sans retirer la progression naturelle. L'héritage facultatif transmet un pourcentage de votre niveau à votre prochain personnage, avec de nouveaux points à dépenser.

Compatible avec le solo, le multijoueur, l'écran partagé et la manette. Aucune dépendance obligatoire.

## Comment fonctionne l'avancement

L'XP gagnée dans les compétences prises en charge augmente aussi votre niveau de survivant. Chaque niveau vous donne un point d'avancement, ou AP. Dépensez vos AP avec les boutons **+** à côté des compétences. Par défaut, trois emplacements d'avancement peuvent être occupés en même temps. Pratiquer une compétence améliorée libère ses emplacements à mesure que vous gagnez l'XP que vous avez sautée. Cette XP compte aussi pour le prochain niveau de la compétence.

La maîtrise atteint le maximum effectif d'une compétence, normalement du niveau 9 au 10. Elle coûte 2 AP et nécessite 2 emplacements libres, puis libère ceux de cette compétence. Avec une limite Globale ou Par compétence de 1, un seul emplacement est nécessaire. En mode Libre, aucun. Le coût reste de 2 AP. Une compétence à son maximum effectif ne génère plus d'XP de survivant supplémentaire.

## Gardez une partie de votre progression après la mort

Activez l'héritage du niveau de survivant et choisissez la part transmise à votre prochain personnage dans le même monde. Par exemple, mourir au niveau de survivant 20 avec un héritage de 50% donne à votre prochain personnage le niveau de survivant 10 et 10 AP à dépenser. Les niveaux de compétences ne sont pas copiés, vous répartissez les points hérités. L'héritage est facultatif et désactivé par défaut.

## Réglages

- **Global :** Toutes les compétences partagent une réserve configurable d'emplacements d'avancement, avec une limite par défaut de 3 emplacements actifs au total.
- **Par compétence :** Chaque compétence possède sa propre limite configurable, avec une valeur par défaut pour les compétences personnalisées compatibles et des réglages individuels facultatifs pour celles du jeu de base.
- **Libre :** Supprime les limites d'emplacements d'avancement et les restrictions liées au rattrapage d'XP.
- Réglez la vitesse de l'XP de survivant sans modifier l'XP des compétences. Choisissez si la condition physique, la force, chaque compétence du jeu de base et les compétences personnalisées compatibles contribuent.
- Dans les options des mods, activez des marqueurs d'avancement plus contrastés ou le pourcentage d'XP de survivant du joueur 1 sur la montre numérique.
- Prend en charge toutes les langues standard proposées dans les paramètres de langue de Project Zomboid. Toutes les traductions ont été entièrement réalisées par IA. Si vous remarquez un texte incorrect ou peu clair, merci de le signaler.

**Remarque :** Changer de mode ne réinitialise pas la progression suivie. L'XP naturelle gagnée en mode Libre continue de réduire le rattrapage bleu conservé. Revenir au mode Global ou Par compétence ne restaure que ce qu'il reste à rattraper.

## Ajouter ou retirer SLA

SLA peut être ajouté ou retiré d'une sauvegarde existante. Les compétences restent, sans niveaux de survivant rétroactifs. Le désactiver masque l'interface mais conserve les niveaux achetés avec des AP. Le réactiver restaure son état et tient compte de la progression compatible pendant son absence. Avant de changer de mods, je recommande de sauvegarder vos mondes importants.

## Serveurs dédiés et hébergement

Les administrateurs peuvent accorder de l’XP de survivant ou des niveaux entiers aux profils existants en ligne ou hors ligne. Les attributions hors ligne sont immédiates. Effacer les améliorations libère les emplacements sans rembourser les AP ni modifier l’XP des compétences. Pour un personnage hors ligne, cette action reste en attente et annulable jusqu’à sa reconnexion. Modifier un niveau dans les statistiques du joueur efface le suivi de cette compétence.

SLA utilise les sauvegardes normales de Project Zomboid. Sur les serveurs dédiés et hébergés, activez SaveWorldEveryMinutes et arrêtez le serveur normalement.

## Compatibilité

- **Incompatible : [RPG Skills Systems B42 / RPGMenu](https://steamcommunity.com/sharedfiles/filedetails/?id=3666281346)**
- **Actuellement non pris en charge : [Beyond Ten - Level 15 Skills](https://steamcommunity.com/sharedfiles/filedetails/?id=3765241705) et [Seesaw Game](https://steamcommunity.com/sharedfiles/filedetails/?id=3515515643)**. Ces mods remplacent directement des règles de progression dont dépend SLA.
- **Dépend de l'ordre de chargement : [Detailed Skill Tooltips](https://steamcommunity.com/sharedfiles/filedetails/?id=3572846242)**. Chargez SLA après Detailed Skill Tooltips pour ajouter son texte de rattrapage bleu aux infobulles étendues de DST. Si SLA est chargé en premier, seul ce texte est remplacé. La progression de survivant et les infobulles des boutons + restent fonctionnelles.
- **Testés ensemble : [Detailed Skill Tooltips](https://steamcommunity.com/sharedfiles/filedetails/?id=3572846242), [Toughness Skill](https://steamcommunity.com/sharedfiles/filedetails/?id=3545533939) et [Show Skill XP Gain B42.20](https://steamcommunity.com/sharedfiles/filedetails/?id=3776490883)**. Cette combinaison a fonctionné sans problème pendant les tests, mais la compatibilité avec tous les mods d'interface ou de compétences personnalisées ne peut pas être garantie.
- Les mods qui remplacent la gestion de l’XP, les plafonds ou courbes des compétences, leur panneau, les menus des joueurs ou la montre numérique peuvent entrer en conflit. SLA désactive l’intégration concernée si ses points d’accroche sont remplacés. Les compétences personnalisées nécessitent une courbe d’XP exploitable et des événements d’XP pris en charge. Les modifications directes ou les progressions sans ces événements ne donnent pas d’XP de survivant.

## Utilisation de l'IA

Tout le code a été écrit avec l'IA. Le concept, le design, les tests, le débogage et les décisions de publication sont les miens. J'ai personnellement passé des heures à tester SLA et à corriger les problèmes. Je comprends et respecte votre choix si vous préférez éviter les mods développés avec l'IA.

## Soutien

- Les dons sur [Ko-fi](https://ko-fi.com/skeptic043) sont facultatifs. Aucune fonction du mod n'est payante.

## Informations du mod

- Développé/testé sur la version : 42.20.4
- Dépendances obligatoires : Aucune
- Licence : MIT
- [Code source et suivi des problèmes](https://github.com/Skeptic043/survivor-leveling-and-advancement)
