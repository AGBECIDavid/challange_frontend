.pragma library

// Tokens de design — source unique de toute valeur visuelle du projet.
//
// Aucune couleur, taille, duree ou epaisseur ne doit apparaitre en dur dans un
// composant : tout passe par ce fichier (skill hmi-design, §8.1).
//
// Note sur la directive ci-dessus : le point initial est requis dans une
// ressource .js, et elle doit etre la toute PREMIERE chose du fichier — pas
// meme un commentaire avant elle, sinon qt_add_qml_module ne la detecte pas
// comme bibliotheque et re-evalue le fichier dans chaque document importateur.

// ---------------------------------------------------------------------------
// Couleurs (skill §3)
// ---------------------------------------------------------------------------

// Fond general. Presque noir, tres legerement bleute. C'est un vide, pas une
// surface : ni degrade, ni texture, ni vignettage.
var bg = "#07090C";

// Zones tres rarement necessaires. A eviter.
var surface = "#101318";

// Arcs et graduations inactifs.
var track = "#1E242C";

// Vitesse, odometre. Contraste ~16:1 sur bg.
var textPrimary = "#EAF0F5";

// Unites, libelles. ~5,5:1 sur bg : suffisant pour un libelle statique,
// INSUFFISANT pour une valeur lue en roulant. Ne jamais y mettre un nombre.
var textSecondary = "#7A848F";

// Arc de vitesse actif, remplissage de la jauge.
// Un seul accent dans tout le projet.
var accent = "#5FD3B4";

// Reserve.
var warn = "#F5A524";

// Source invalide, defaut.
var danger = "#F4483B";

// ---------------------------------------------------------------------------
// Typographie (skill §3)
// ---------------------------------------------------------------------------

// Famille bundlee, jamais une police systeme : le rendu doit etre identique
// sur le Pi et sur la machine de developpement. Inter, licence OFL, chargee
// par FontLoader depuis assets/fonts/ (voir Main.qml).
// Les deux fichiers statiques Light (300) et Regular (400) s'enregistrent tous
// deux sous cette meme famille.
var fontFamily = "Inter";

// Le chiffre de vitesse.
//
// Ecart assume avec le skill, qui specifie 200 : seules les graisses 300 et
// 400 sont embarquees, et 300 est de toute facon le meilleur choix de
// lisibilite en plein soleil (skill §1). Le skill est a mettre a jour.
var sizeSpeed = 180;
var weightSpeed = 300;

// Kilometrage.
var sizeOdometer = 34;
var weightOdometer = 300;

// « km/h », « km ». Capitales, interlettrage +8 %.
var sizeUnit = 22;
var weightUnit = 400;

// Libelles secondaires.
var sizeLabel = 16;
var weightLabel = 400;

// Interlettrage des unites en capitales, exprime en fraction de la taille.
var trackingUnit = 0.08;

// ---------------------------------------------------------------------------
// Espacement (skill §3) — echelle fermee, rien en dehors
// ---------------------------------------------------------------------------

var space4 = 4;
var space8 = 8;
var space12 = 12;
var space16 = 16;
var space24 = 24;
var space32 = 32;
var space48 = 48;
var space64 = 64;
var space96 = 96;

// ---------------------------------------------------------------------------
// Durees (skill §3)
// ---------------------------------------------------------------------------

// Lissage de la vitesse. Legerement au-dessus de la periode de la source
// (50 ms) pour absorber la gigue, sans trainer derriere la donnee.
var durSpeed = 60;

// Jauge d'accelerateur.
var durThrottle = 80;

// Apparition/disparition d'un indicateur.
var durFade = 160;

// ---------------------------------------------------------------------------
// Geometrie du cadran (skill §6 et §7)
//
// Ces tokens ne figurent pas dans les tableaux du §3, mais le §8.1 interdit
// toute valeur visuelle en dur dans un composant. Les NOMS sont donc de moi,
// les VALEURS viennent litteralement du skill : §6 pour les epaisseurs, le
// balayage et le pas de graduation, §7 pour le diametre et la marge.
// ---------------------------------------------------------------------------

// Diametre du cadran (§7 : « ~520 px »).
var dialDiameter = 520;

// Epaisseur de l'arc actif (§6). En dessous de 10 px, illisible en plein
// soleil ; 14 px pour l'arc porteur d'information.
var dialActiveWidth = 14;

// Epaisseur de la piste inactive (§6).
var dialTrackWidth = 10;

// Balayage : 270°, de 135° a 405°, sens horaire, origine a 3 h.
// Ouverture vers le bas, convention automobile.
var dialStartAngle = 135;
var dialSweepAngle = 270;

// Graduations tous les 5 km/h, majeures tous les 10.
var dialMinorTickStep = 5;
var dialMajorTickStep = 10;

// Traits de graduation. Aucun trait de moins de 3 px (§1, lecture au soleil).
var dialMinorTickWidth = 3;
var dialMinorTickLength = 12;
var dialMajorTickWidth = 4;
var dialMajorTickLength = 18;

// Marge exterieure de la mise en page (§7).
var layoutMargin = 48;

// Position horizontale du centre du cadran, en fraction de la largeur (§7).
var dialCenterXRatio = 0.45;
