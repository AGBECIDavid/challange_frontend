# Validation CAN — procédure de test sur bus virtuel

> ## ⚠ Statut de ce document
>
> Ce document est une **procédure de test**, pas du code. Conformément au
> périmètre du projet ([`CONVENTIONS.md`](../CONVENTIONS.md)), le dépôt ne
> contient **aucun code CAN et aucune lecture matérielle**. Les scripts donnés
> ici sont des outils de vérification hors application : ils ne lisent aucun
> matériel, ne sont pas compilés, et vivent dans ce document — pas dans `src/`.
>
> Il se lit en deux moitiés, et la distinction est importante :
>
> | Partie | Exécutable |
> |---|---|
> | §1 à §3 — bus virtuel, mise en place, **vérification de l'encodage** | **Oui, aujourd'hui.** Ne demande aucun code applicatif. Les résultats du §3.5 ont été réellement mesurés. |
> | §4 et §5 — tests de la source CAN, séance conjointe | **Non.** `CanDataSource` n'existe pas. Procédure à suivre le jour où il sera écrit. |
>
> Les identifiants et l'encodage testés ici sont ceux **proposés** par
> [`docs/interface-can.md`](interface-can.md), qui ne sont pas convenus avec le
> Groupe III. Ce document valide donc la **cohérence interne** de la
> proposition, pas sa justesse vis-à-vis du VCU réel.

---

## 1. Ce qu'est un bus CAN virtuel

### 1.1 Le principe

`vcan` est un pilote du noyau Linux qui crée une interface réseau se comportant
comme un contrôleur CAN, **sans le moindre matériel**. Elle apparaît dans
`ip link` à côté des cartes Ethernet, elle accepte les mêmes sockets `AF_CAN`,
elle transporte les mêmes structures `struct can_frame`.

Le mécanisme tient en une phrase : **tout ce qu'un processus écrit sur
l'interface, tous les autres processus abonnés à cette interface le lisent.**
Le noyau fait office de bus. Il n'y a ni fil, ni transceiver, ni horloge de bit.

```
  processus A (firmware)                    processus B (IHM Qt)
        |                                          ^
        | write(sock, &frame)                      | read(sock, &frame)
        v                                          |
  +---------------------------------------------------+
  |            vcan0  —  pilote noyau                  |
  +---------------------------------------------------+
```

C'est exactement l'architecture décrite par l'énoncé — « le firmware ouvre un
socket `AF_CAN` et y écrit ses trames ; l'application Qt ouvre un socket sur la
même interface et les lit » — à ceci près que l'interface est logicielle. Le
code applicatif des deux côtés est **rigoureusement le même** que sur un bus
réel : `socket(PF_CAN, SOCK_RAW, CAN_RAW)`, `bind()` sur `vcan0` plutôt que
`can0`. C'est le seul caractère qui change.

### 1.2 Ce que ça permet

- Vérifier qu'un encodage est correct — un octet est un octet, `vcan` ne
  transforme rien.
- Vérifier l'aiguillage par identifiant, les longueurs (DLC), l'endianness, les
  facteurs d'échelle, la saturation, le bornage.
- Vérifier la logique temporelle applicative : périodes d'émission, chien de
  garde, compteur de séquence, comportement en cas de silence.
- Faire travailler ensemble deux équipes qui n'ont pas encore de véhicule, sur
  une seule machine, sans budget matériel.
- Rejouer une capture à l'identique, autant de fois qu'on veut. Un bug
  reproductible est un bug corrigeable.

### 1.3 Ce que ça ne permet pas — et ce n'est pas un détail

**`vcan` n'est pas un substitut à un essai sur véhicule.** Il valide la couche
logicielle, et strictement elle.

| Absent de `vcan` | Conséquence |
|---|---|
| **Arbitrage** | Le noyau délivre les trames dans l'ordre où elles sont écrites. Le choix des identifiants `0x100` / `0x300` / `0x500`, justifié par la priorité d'arbitrage au §2 de [`interface-can.md`](interface-can.md), **n'est donc pas testé ici**. On pourrait inverser les trois identifiants sans qu'aucun test de ce document ne bronche. |
| **Débit de bit, terminaison, longueur de ligne** | Aucune notion de 125/250/500 kbit/s. Un bus saturé et un bus vide se comportent identiquement. La charge de 2,9 kbit/s annoncée n'est ni vérifiable ni vérifiée. |
| **Bruit électrique, erreurs de trame** | Pas de CRC de niveau trame invalidé, pas de bit stuffing, pas de compteur d'erreurs, pas de passage en `bus-off`. Le taux de perte est nul par construction. |
| **Latence et gigue réelles** | La gigue mesurée est celle de l'ordonnanceur Linux local, pas celle d'un contrôleur CAN. Le seuil de chien de garde à trois périodes ne peut donc pas être *validé* ici — seulement *exercé*. |
| **Charge CPU du décodage sur cible** | Tout tourne sur une machine de développement, pas sur le Raspberry Pi 4. |

La conclusion à retenir : **un test `vcan` qui passe ne prouve pas que le
système marchera sur véhicule ; un test `vcan` qui échoue prouve qu'il ne
marchera pas.** C'est un filtre, pas une garantie. Voir §6.

---

## 2. Mise en place

### 2.1 Prérequis, et comment vérifier qu'ils sont réunis

| Élément | Commande de vérification | Attendu |
|---|---|---|
| Module noyau `vcan` | `modinfo vcan` | Une fiche de module, pas `ERROR: Module vcan not found` |
| Support `vcan` dans `iproute2` | `ip link help 2>&1 \| grep -w vcan` | `vcan` apparaît dans la liste des types |
| `can-utils` | `which cansend candump cangen` | Trois chemins |

Si `modinfo vcan` échoue, le noyau a été compilé sans `CONFIG_CAN_VCAN`. Sur
Debian et dérivés c'est le paquet `linux-modules-extra-$(uname -r)` qui le
fournit ; sur un noyau personnalisé, il faut le recompiler. **Sans ce module,
rien de ce document n'est exécutable.**

Installation de `can-utils` — 143 ko de téléchargement, 726 ko sur disque,
aucune dépendance hors `libc6` :

```sh
sudo apt install can-utils
```

### 2.2 Créer le bus

```sh
sudo modprobe vcan
sudo ip link add dev vcan0 type vcan
sudo ip link set up vcan0
```

Vérification :

```sh
ip -d link show vcan0
```

```
13: vcan0: <NOARP,UP,LOWER_UP> mtu 2060 qdisc noqueue state UNKNOWN mode DEFAULT
    link/can  promiscuity 0 allmulti 0 minmtu 0 maxmtu 0
    vcan addrgenmode eui64 numtxqueues 1 numrxqueues 1 ...
```

Les deux points à lire : `link/can` (c'est bien une interface CAN, pas
Ethernet) et `UP,LOWER_UP` (elle est montée). L'état `UNKNOWN` est normal pour
`vcan` — il n'y a pas de porteuse physique à détecter.

### 2.3 Démonter le bus

```sh
sudo ip link set down vcan0
sudo ip link delete vcan0
```

L'interface ne survit pas au redémarrage : les trois commandes du §2.2 sont à
rejouer à chaque session. C'est une bonne chose — aucun état ne persiste d'une
séance de test à l'autre.

### 2.4 Les deux outils

```sh
candump vcan0                    # écoute tout
candump -L vcan0                 # format « log », rejouable par canplayer
candump -ta vcan0                # horodatage absolu, octets espacés
candump 'vcan0,100:7FF'          # n'écoute que l'identifiant 0x100
candump -l vcan0                 # écrit dans un fichier candump-*.log

cansend vcan0 100#3A0E4A03000000B1        # une trame, 8 octets
cangen vcan0 -I 100 -L 8 -g 50 -D 8813C80000000000   # rafale périodique
```

**Piège vérifié sur cette machine, à connaître avant de perdre une heure :**
`cansend` **tronque silencieusement** une charge utile de plus de 8 octets et
retourne le code de sortie 0.

```
$ cansend vcan0 100#112233445566778899 ; echo $?
0
$ candump -L vcan0
(…) vcan0 100#1122334455667788          ← le 99 a disparu, sans un mot
```

Un chiffre hexadécimal de trop dans une trame écrite à la main produit donc une
trame **valide et fausse**, sans erreur. C'est la première raison pour laquelle
les trames de ce document sont **générées par script** (§3.3) et non tapées.

---

## 3. Vérification de l'encodage — exécutable aujourd'hui

> **C'est la partie la plus utile de ce document.** Elle ne demande ni
> `CanDataSource`, ni Qt, ni la moindre ligne du projet. Elle répond à une
> question précise : *les tableaux d'encodage de [`interface-can.md`](interface-can.md)
> sont-ils cohérents — une valeur physique donnée produit-elle bien les octets
> annoncés, et ces octets redonnent-ils bien la valeur de départ ?*

### 3.1 Ce qui est vérifié, et ce qui ne peut pas l'être

Vérifier un encodage sans firmware, c'est vérifier un **aller-retour** :
valeur physique → octets → valeur physique. Si le tour est exact à la
résolution près, l'encodage est cohérent. Cela ne dit évidemment **rien** sur
la question de savoir si le Groupe III utilise ce format — seulement que le
format proposé se tient.

Quatre grandeurs sont concernées, correspondant aux quatre signaux du contrat
qui transitent par une trame (`sourceValid` est déduit, pas transmis) :

| Signal | Trame | Type | Facteur | Plage d'encodage |
|---|---|---|---|---|
| `Speed` | `0x100` octets 0–1 | uint16 LE | 0,01 | 0 à 655,35 km/h |
| `ThrottlePosition` | `0x100` octet 2 | uint8 | 0,5 | 0 à 127,5 % |
| `TotalDistance` | `0x300` octets 0–2 | uint24 LE | 0,1 | 0 à 1 677 721,5 km |
| `MaxSpeed` | `0x500` octets 0–1 | uint16 LE | 0,01 | 0 à 655,35 km/h |

### 3.2 Choix des valeurs de test

Les valeurs ne sont pas prises au hasard : chacune exerce un cas limite
identifié.

| Cas limite | Pourquoi il compte |
|---|---|
| **Zéro** | Le seul motif entièrement nul. Un octet oublié ou un décalage d'index ne se voient pas sur une trame de zéros — mais un décodeur qui refuse le zéro se voit tout de suite. |
| **Plafond du véhicule** (50 km/h, 100 %) | La valeur nominale maximale. Doit passer sans saturer. |
| **Plafond de l'encodage** (655,35 km/h, 127,5 %, 1 677 721,5 km) | La dernière valeur représentable. C'est là que se logent les erreurs de type signé/non signé : un uint16 lu comme int16 rend −1 au lieu de 65535. |
| **Décimale non ronde** (37,3 % ; 36,427 km/h) | Force la quantification. Vérifie que l'arrondi est fait dans le bon sens et que l'erreur reste bornée par un demi-pas. |
| **Dépassement** (700 km/h ; 140 % ; 2 000 000 km) | Au-delà du représentable. Vérifie que la saturation est propre et non un repliement modulo. |
| **Dépassement du véhicule, pas de l'encodage** (52,5 km/h ; 110 %) | Le cas vicieux : la trame est parfaitement légale, la valeur est parfaitement décodable, et elle dépasse quand même le plafond du véhicule. C'est à l'IHM de borner, pas à l'encodage. |

Le dernier cas mérite d'être souligné. `52,50 km/h` s'encode en `82 14`, se
décode en `52,50`, et **rien dans la trame ne signale un problème**. C'est
`CanDataSource` qui devra borner à `maxSpeedKph`, faute de quoi l'aiguille du
cadran sortira de sa graduation. Le §4.5 en fait un test à part entière.

### 3.3 Générateur de trames

Ce script produit les commandes `cansend` à partir de valeurs physiques. Il ne
lit aucun matériel, n'ouvre aucun socket, et n'appartient pas à l'application :
il se colle dans un fichier temporaire, hors du dépôt.

```python
#!/usr/bin/env python3
"""Genere les commandes cansend a partir de valeurs physiques.
Encodage : docs/interface-can.md. Outil de test, hors application."""

def crc8_j1850(data):
    """CRC-8/SAE-J1850 : poly 0x1D, init 0xFF, xorout 0xFF."""
    crc = 0xFF
    for b in data:
        crc ^= b
        for _ in range(8):
            crc = ((crc << 1) ^ 0x1D) & 0xFF if crc & 0x80 else (crc << 1) & 0xFF
    return crc ^ 0xFF

def quant(phys, factor, bits):
    """Valeur physique -> entier brut, sature aux bornes de l'encodage."""
    return max(0, min((1 << bits) - 1, round(phys / factor)))

def dynamics(speed_kph, throttle_pct, seq):
    """0x100 VEHICLE_DYNAMICS, 8 octets."""
    raw = quant(speed_kph, 0.01, 16)
    body = [raw & 0xFF, (raw >> 8) & 0xFF,
            quant(throttle_pct, 0.5, 8), seq & 0xFF, 0x00, 0x00, 0x00]
    return ''.join(f"{b:02X}" for b in body + [crc8_j1850(body)])

def odometer(km, seq):
    """0x300 ODOMETER, 4 octets."""
    r = quant(km, 0.1, 24)
    return ''.join(f"{b:02X}" for b in
                   [r & 0xFF, (r >> 8) & 0xFF, (r >> 16) & 0xFF, seq & 0xFF])

def config(max_kph):
    """0x500 VEHICLE_CONFIG, 2 octets."""
    r = quant(max_kph, 0.01, 16)
    return f"{r & 0xFF:02X}{(r >> 8) & 0xFF:02X}"

if __name__ == "__main__":
    cases = [(0.0, 0.0), (36.42, 0.0), (36.42, 37.0), (37.30, 37.3),
             (50.0, 100.0), (655.35, 127.5), (700.0, 140.0), (52.5, 110.0)]
    for seq, (s, t) in enumerate(cases, 1):
        print(f"cansend vcan0 100#{dynamics(s, t, seq)}")
    for seq, km in enumerate([0.0, 1234.5, 12345.6, 1677721.5, 2000000.0], 1):
        print(f"cansend vcan0 300#{odometer(km, seq)}")
    print(f"cansend vcan0 500#{config(50.0)}")
```

### 3.4 Décodeur inverse

Celui-ci lit une capture `candump -L` et refait le chemin en sens contraire.
C'est lui qui constitue la vérification : il ne connaît pas les valeurs de
départ, il ne voit que les octets réellement passés sur le bus.

```python
#!/usr/bin/env python3
"""Decodeur inverse : capture candump -L -> valeurs physiques.
Usage : ./decode.py capture.log     Outil de test, hors application."""
import re, sys

def crc8_j1850(data):
    crc = 0xFF
    for b in data:
        crc ^= b
        for _ in range(8):
            crc = ((crc << 1) ^ 0x1D) & 0xFF if crc & 0x80 else (crc << 1) & 0xFF
    return crc ^ 0xFF

MAX_SPEED_KPH = 50.0   # publie par 0x500 ; ce que l'IHM doit faire respecter

def decode(cid, d):
    if cid == 0x100:
        if len(d) != 8:
            return f"*** DLC={len(d)}, attendu 8 -- trame a rejeter ***"
        raw   = d[0] | (d[1] << 8)
        speed = raw * 0.01
        thr   = d[2] * 0.5
        crc   = crc8_j1850(d[0:7])
        return (f"speedKph={speed:.2f} (borne {min(speed, MAX_SPEED_KPH):.2f}) "
                f"throttlePercent={thr:.1f} (borne {min(thr, 100.0):.1f}) "
                f"seq={d[3]} crc={d[7]:02X} attendu={crc:02X} "
                f"{'OK' if crc == d[7] else '*** MISMATCH ***'}")
    if cid == 0x300:
        if len(d) != 4:
            return f"*** DLC={len(d)}, attendu 4 -- trame a rejeter ***"
        raw = d[0] | (d[1] << 8) | (d[2] << 16)
        return f"odometerKm={raw * 0.1:.1f} seq={d[3]}"
    if cid == 0x500:
        if len(d) != 2:
            return f"*** DLC={len(d)}, attendu 2 -- trame a rejeter ***"
        return f"maxSpeedKph={(d[0] | (d[1] << 8)) * 0.01:.2f}"
    return "identifiant hors interface -- ignore"

pat = re.compile(r'\(([\d.]+)\)\s+(\S+)\s+([0-9A-Fa-f]+)#([0-9A-Fa-f]*)')
for line in open(sys.argv[1]):
    m = pat.match(line.strip())
    if not m:
        continue
    _, _, cid_s, data_s = m.groups()
    cid = int(cid_s, 16)
    print(f"0x{cid:03X}  {data_s:<18}  {decode(cid, bytes.fromhex(data_s))}")
```

### 3.5 Exécution et résultats — **réellement mesurés**

```sh
python3 gen.py > send.sh
candump -L vcan0 > capture.log &
sh send.sh
kill %1
python3 decode.py capture.log
```

Environnement de la mesure : Linux 6.19.11 (Kali), `iproute2-6.19.0`,
`can-utils 2023.03-1`, interface `vcan0`.

#### `0x100` — `VEHICLE_DYNAMICS`

| Valeur émise | Octets observés sur le bus | Valeur décodée | CRC | Verdict |
|---|---|---|---|---|
| 0,00 km/h / 0,0 % | `00 00 00 01 00 00 00 97` | 0,00 km/h / 0,0 % | ✅ | **exact** |
| 36,42 km/h / 0,0 % | `3A 0E 00 02 00 00 00 10` | 36,42 km/h / 0,0 % | ✅ | **exact** |
| 36,42 km/h / 37,0 % | `3A 0E 4A 03 00 00 00 B1` | 36,42 km/h / 37,0 % | ✅ | **exact** |
| 37,30 km/h / 37,3 % | `92 0E 4B 04 00 00 00 33` | 37,30 km/h / **37,5 %** | ✅ | quantifié — écart 0,2 %, < ½ pas |
| 50,00 km/h / 100,0 % | `88 13 C8 05 00 00 00 BF` | 50,00 km/h / 100,0 % | ✅ | **exact** — plafond véhicule |
| 655,35 km/h / 127,5 % | `FF FF FF 06 00 00 00 70` | 655,35 km/h / 127,5 % | ✅ | **exact** — plafond encodage |
| **700 km/h / 140 %** | `FF FF FF 07 00 00 00 ED` | 655,35 km/h / 127,5 % | ✅ | **saturé**, pas replié |
| **52,50 km/h / 110,0 %** | `82 14 DC 08 00 00 00 0C` | 52,50 km/h / 110,0 % | ✅ | trame **légale**, hors plage véhicule → l'IHM doit borner à 50,00 / 100,0 |
| 36,427 km/h | `3B 0E 00 09 00 00 00 6B` | 36,43 km/h | ✅ | arrondi au supérieur |
| 36,425 km/h | `3A 0E 00 0A 00 00 00 8C` | 36,42 km/h | ✅ | arrondi au pair (Python) — voir note |
| 0,004 km/h | `00 00 00 0B 00 00 00 2C` | 0,00 km/h | ✅ | arrondi à zéro |
| 0,006 km/h | `01 00 00 0C 00 00 00 85` | 0,01 km/h | ✅ | premier pas non nul |

**Note sur `36,425`.** Python arrondit au pair le plus proche ; C et Qt
(`qRound`) arrondissent au supérieur. Les deux rendent `36,42` ou `36,43`, soit
un écart d'un pas de 0,01 km/h — **0,24 px sur l'arc du cadran**, donc sans
conséquence. Le point mérite quand même d'être posé au Groupe III : si leur
firmware et notre décodeur n'arrondissent pas pareil, les journaux des deux
côtés ne concorderont pas à l'unité près, et quelqu'un y perdra du temps.

#### `0x300` — `ODOMETER`

| Valeur émise | Octets observés | Valeur décodée | Verdict |
|---|---|---|---|
| 0,0 km | `00 00 00 01` | 0,0 km | **exact** |
| 1 234,5 km | `39 30 00 02` | 1 234,5 km | **exact** |
| 12 345,6 km | `40 E2 01 03` | 12 345,6 km | **exact** — exerce les 3 octets |
| 1 677 721,5 km | `FF FF FF 04` | 1 677 721,5 km | **exact** — plafond uint24 |
| **2 000 000 km** | `FF FF FF 05` | 1 677 721,5 km | **saturé**, pas replié |

#### `0x500` — `VEHICLE_CONFIG`

| Valeur émise | Octets observés | Valeur décodée | Verdict |
|---|---|---|---|
| 50,00 km/h | `88 13` | 50,00 km/h | **exact** — identique à `Speed`, comme annoncé |

#### Conclusion de la vérification

**Les quatre encodages de [`interface-can.md`](interface-can.md) sont
cohérents.** Sur les 18 valeurs testées, l'aller-retour est exact au pas de
quantification près dans tous les cas ; les trois dépassements saturent
proprement, sans repliement modulo. L'endianness petit-boutiste est confirmée
par lecture directe des octets (`88 13` pour 5000, et non `13 88`).

Une seule remarque de fond, déjà relevée au §3.2 : `52,50 km/h` produit une
trame parfaitement valide dont la valeur dépasse le plafond du véhicule.
**L'encodage ne protège de rien à ce sujet** — le bornage est une
responsabilité de `CanDataSource`, testée au §4.5.

### 3.6 Une erreur réellement attrapée par la procédure

Lors d'un premier essai, les trames avaient été écrites à la main en
incrémentant le compteur de séquence sans recalculer le CRC. Le décodeur l'a
signalé immédiatement :

```
0x100  3A0E4A0200000095    speedKph=36.42 ... seq=2 crc=95 attendu=2C *** MISMATCH ***
0x100  8813C803000000F3    speedKph=50.00 ... seq=3 crc=F3 attendu=D6 *** MISMATCH ***
```

Les valeurs physiques, elles, se décodaient parfaitement. Sans vérification du
CRC, l'erreur serait passée inaperçue — et c'est précisément le mode de
défaillance qu'un checksum applicatif est censé attraper. **C'est l'argument
le plus concret en faveur du champ `Checksum` du §3.1 de
[`interface-can.md`](interface-can.md)**, dont l'utilité était présentée comme
discutable.

Deux conclusions pratiques : les trames de test se génèrent par script, jamais
à la main ; et le décodeur doit vérifier le CRC, sans quoi il valide des trames
corrompues.

---

## 4. Procédure de test au moment de la substitution

> ## 🚫 Cette section n'est pas exécutable aujourd'hui
>
> Elle suppose l'existence de `src/CanDataSource.qml`, qui **n'existe pas** et
> dont l'écriture est hors du périmètre de ce dépôt. C'est une procédure à
> suivre le jour où ce composant sera écrit, pas un compte rendu de test.
>
> Les commandes `cansend`, `candump` et `cangen` ci-dessous ont en revanche été
> **vérifiées syntaxiquement sur `vcan0`** : elles émettent bien ce qui est
> annoncé. Seul le comportement de l'IHM reste à observer.

Prérequis commun à tous les tests : le bus est monté (§2.2) et l'application
tourne, câblée sur `CanDataSource`.

```sh
qml src/Main.qml -- --windowed --fps
```

Le mode fenêtré permet de garder un terminal visible à côté ; `--fps` sert au
test §4.7.

### 4.1 Rampe de vitesse réaliste

**But** — vérifier que l'affichage suit une progression continue, sans à-coup
ni retard visible.

La rampe reproduit l'accélération du modèle physique : 0 → 50 km/h en 12 s à
20 Hz, soit 240 trames. Le compteur de séquence progresse à chaque émission.

```sh
python3 - <<'PY' > ramp.sh
def crc8(d):
    c = 0xFF
    for b in d:
        c ^= b
        for _ in range(8):
            c = ((c << 1) ^ 0x1D) & 0xFF if c & 0x80 else (c << 1) & 0xFF
    return c ^ 0xFF

v, dt = 0.0, 0.05
for i in range(240):
    a = 1.5 * (1 - v / (50 / 3.6))          # VehicleModel : plein gaz
    v = max(0.0, v + a * dt)
    raw = min(65535, round(v * 3.6 / 0.01))
    body = [raw & 0xFF, (raw >> 8) & 0xFF, 200, i & 0xFF, 0, 0, 0]
    print(f"cansend vcan0 100#{''.join(f'{b:02X}' for b in body + [crc8(body)])}")
    print("sleep 0.05")
PY
sh ramp.sh
```

Il faut aussi émettre `0x500` en continu, sans quoi `maxSpeedKph` n'est jamais
reçue. Dans un second terminal :

```sh
while true; do cansend vcan0 500#8813; sleep 1; done
```

**Comportement attendu** — l'aiguille part de 0 et rejoint 50 km/h en environ
12 secondes, en ralentissant à l'approche du plafond (l'accélération décroît
en `1 − v/vMax`). La jauge d'accélérateur affiche 100 % en permanence.
L'odomètre ne bouge pas : `0x300` n'est pas émis dans ce test.

**Critères de réussite**

- [ ] L'aiguille progresse **sans saut visible**. La source publie à 20 Hz et
      le rendu tourne à 60 Hz : c'est le `Behavior` de `SpeedDial` qui interpole.
      Un mouvement saccadé signale un `Behavior` désactivé ou une durée mal
      réglée, pas un problème de bus.
- [ ] La valeur numérique affichée correspond à ±0,1 km/h près à la dernière
      trame émise, lue dans une capture `candump -L` prise en parallèle.
- [ ] L'aiguille **ne dépasse jamais** la graduation 50.
- [ ] `SOURCE INVALIDE` **n'apparaît à aucun moment** pendant la rampe.

**Note de mesure** : une boucle `cansend` + `sleep 0.05` a été chronométrée à
**51,9 ms d'intervalle moyen** (min 51,7, max 52,1) sur cette machine — environ
2 ms de surcoût par itération, dus au lancement d'un processus par trame. C'est
**tolérable pour un test d'affichage, mais impropre à un test de chien de
garde** : un seuil à 150 ms se réglerait sur une cadence de 52 ms au lieu de
50. Pour toute mesure temporelle fine, utiliser `cangen`, qui émet depuis un
seul processus :

```sh
cangen vcan0 -I 100 -L 8 -g 50 -D 8813C80000000000
```

Cadence mesurée : **50,1 ms**, gigue inférieure à 0,2 ms. En contrepartie,
`cangen` émet une charge utile **constante** : le compteur de séquence ne
progresse pas, et la source doit donc lever `sourceValid` à faux au bout de
trois trames (§4.4). `cangen` convient aux tests de cadence, pas aux tests de
contenu.

### 4.2 Chien de garde — arrêt de l'émission

**But** — vérifier que `sourceValid` passe à faux dans le délai spécifié
(3 périodes = 150 ms pour `0x100`) quand les trames cessent.

```sh
# Emission nominale
cangen vcan0 -I 100 -L 8 -g 50 -D 8813C80000000000 &
GEN=$!
sleep 5
# Coupure franche, horodatee
date +%s.%N ; kill $GEN
```

**Comportement attendu** — l'indicateur `SOURCE INVALIDE` apparaît en fondu
(`Theme.danger`) dans les 150 ms qui suivent l'arrêt. Le fondu lui-même prend
le temps prévu par `Theme` ; c'est le **déclenchement** qui doit tenir dans
150 ms, pas la fin de l'animation.

**Critères de réussite**

- [ ] `SOURCE INVALIDE` apparaît. Un indicateur qui ne s'allume jamais signale
      un chien de garde absent ou jamais armé.
- [ ] Le délai entre la dernière trame de `candump -ta` et l'apparition est
      **compris entre 100 et 200 ms**. Trop court : le seuil est sous les
      3 périodes et se déclenchera sur une perte isolée. Trop long : des données
      périmées restent affichées comme valides.
- [ ] Les valeurs affichées **ne retombent pas à zéro**. Afficher « 0 km/h » sur
      un véhicule en mouvement est le mode de défaillance explicitement rejeté
      au §5.3 de [`interface-can.md`](interface-can.md).
- [ ] Aucun message d'erreur QML sur la sortie standard : une source hors
      service ne doit pas produire d'exception.

### 4.3 Chien de garde — cas de l'odomètre

**But** — vérifier que le chien de garde de `0x300` a bien son propre seuil
(3 s), et qu'une absence d'odomètre n'invalide pas la vitesse à tort.

```sh
cangen vcan0 -I 100 -L 8 -g 50 -D 8813C80000000000 &   # 0x100 continue
# 0x300 n'est jamais emis
```

**Comportement attendu** — à trancher avec le Groupe III, et c'est un point
ouvert du §7 de [`interface-can.md`](interface-can.md). Deux lectures
défendables : soit `sourceValid` tombe (une des trames du contrat manque), soit
seul l'odomètre est marqué périmé et la vitesse reste valide. **Le test
consiste ici à constater le choix effectivement implémenté et à vérifier qu'il
est cohérent avec la documentation**, pas à imposer l'un des deux.

**Critères de réussite**

- [ ] Le comportement observé est celui décrit dans la documentation de
      `CanDataSource`.
- [ ] Il est **stable** : pas d'oscillation de `sourceValid` à chaque période
      de 3 s.

### 4.4 Valeur figée — compteur de séquence

**But** — vérifier le mécanisme du §5.2 de [`interface-can.md`](interface-can.md) :
des trames qui arrivent à l'heure avec un contenu périmé doivent être
détectées. C'est le défaut que le chien de garde ne voit pas.

```sh
# Trame strictement identique, seq bloque a 0x05, a la bonne cadence
while true; do cansend vcan0 100#8813C805000000BF; sleep 0.05; done
```

Vérification que l'émission est bien conforme — capture réelle :

```
(…) vcan0 100#8813C805000000BF     seq=5 crc=BF OK
(…) vcan0 100#8813C805000000BF     seq=5 crc=BF OK
(…) vcan0 100#8813C805000000BF     seq=5 crc=BF OK
(…) vcan0 100#8813C805000000BF     seq=5 crc=BF OK
```

Les trames sont **valides, ponctuelles et identiques**. Un chien de garde seul
reste muet : c'est exactement la situation d'une passerelle qui rediffuse un
tampon figé.

**Comportement attendu** — `sourceValid` passe à faux après trois trames sans
progression du compteur, soit environ 150 ms, et `SOURCE INVALIDE` apparaît —
alors même que les trames continuent d'arriver.

**Critères de réussite**

- [ ] `SOURCE INVALIDE` apparaît **bien que le bus soit actif**. C'est le seul
      test qui distingue un chien de garde d'un vrai contrôle de fraîcheur.
- [ ] Le délai est du même ordre qu'au §4.2 (~150 ms).
- [ ] **Test de non-régression, indispensable** : rejouer avec un compteur qui
      progresse et une vitesse constante à 0 km/h (véhicule à l'arrêt, moteur
      tournant). `SOURCE INVALIDE` **ne doit pas** apparaître. Sans ce
      contre-test, une implémentation qui invalide sur « données inchangées »
      au lieu de « séquence inchangée » passerait le test précédent tout en
      étant fausse — et déclarerait en panne tout véhicule à l'arrêt.

### 4.5 Bornes — vitesse supérieure au plafond

**But** — vérifier que l'IHM borne une valeur légale mais hors plage véhicule.
Voir §3.2 : l'encodage ne protège de rien ici.

```sh
cansend vcan0 500#8813              # maxSpeedKph = 50,00
sleep 1
cansend vcan0 100#8214DC080000000C  # 52,50 km/h, 110 % -- trame valide
```

Trame vérifiée au §3.5 : elle se décode en `speedKph = 52,50` et
`throttlePercent = 110,0`, CRC correct.

**Comportement attendu** — l'aiguille s'arrête **exactement** sur la graduation
50 et n'en sort pas ; la jauge d'accélérateur sature à 100 %. Aucune sortie
graphique hors du cadran.

**Critères de réussite**

- [ ] L'aiguille **ne dépasse pas** la graduation 50. Une aiguille qui sort de
      l'arc est un défaut visuel immédiatement perceptible.
- [ ] La valeur numérique affiche 50,0 et non 52,5.
- [ ] La jauge d'accélérateur ne dépasse pas sa borne haute.
- [ ] `SOURCE INVALIDE` **n'apparaît pas** : la trame est valide, seule la
      valeur est hors plage. Confondre les deux ferait passer pour une panne
      de bus ce qui est un dépassement de consigne.
- [ ] Variante à tester également : `cansend vcan0 100#FFFFFF0600000070`
      (655,35 km/h, plafond d'encodage). Même attente.

### 4.6 Reprise

**But** — vérifier que le retour à la normale est complet, et qu'aucun état de
panne ne reste collé.

```sh
cangen vcan0 -I 100 -L 8 -g 50 -D 8813C80000000000 &   # nominal
sleep 3
kill %1 ; sleep 2                                       # panne
cangen vcan0 -I 100 -L 8 -g 50 -D 3A0E4A0000000000 &   # reprise, autre valeur
```

Émettre une valeur **différente** à la reprise (36,42 km/h au lieu de 50) est
délibéré : cela distingue un affichage qui s'est réellement remis à jour d'un
affichage resté figé sur l'ancienne valeur.

**Comportement attendu** — `SOURCE INVALIDE` disparaît en fondu dès la première
trame valide reçue, et l'aiguille rejoint 36,42 km/h.

**Critères de réussite**

- [ ] `SOURCE INVALIDE` disparaît en **moins d'une période** après la reprise.
- [ ] L'aiguille converge vers la **nouvelle** valeur, pas l'ancienne.
- [ ] Enchaîner **cinq cycles panne/reprise** sans redémarrer l'application :
      aucune dégradation, aucun état bloqué, aucune fuite d'objet QML. Un
      indicateur qui reste allumé au cinquième cycle signale un état de panne
      non réarmé.
- [ ] L'odomètre **n'a pas décru** au cours de l'exercice, et n'a pas été remis
      à zéro par la coupure — invariant du contrat.

### 4.7 Charge soutenue

**But** — vérifier que la réception ne dégrade pas le rendu.

```sh
cangen vcan0 -I 100 -L 8 -g 10 -D 8813C80000000000 &   # 100 Hz, 5x le nominal
```

**Critères de réussite**

- [ ] Le compteur `--fps` ne chute pas de manière mesurable par rapport à la
      même application alimentée par `SimulatedDataSource`.
- [ ] Aucune croissance continue de la mémoire sur 10 minutes (`ps -o rss=`).
- [ ] L'affichage reste cohérent : pas de valeur aberrante due à une trame lue
      partiellement.

⚠ **Ce test ne dit rien de la cible.** Voir §6.4.

### 4.8 Récapitulatif — feuille de relevé

| § | Test | Résultat | Date | Opérateur |
|---|---|---|---|---|
| 4.1 | Rampe de vitesse | ☐ OK ☐ KO | | |
| 4.2 | Chien de garde — arrêt | ☐ OK ☐ KO | | |
| 4.3 | Chien de garde — odomètre | ☐ OK ☐ KO | | |
| 4.4 | Valeur figée (+ contre-test à l'arrêt) | ☐ OK ☐ KO | | |
| 4.5 | Bornes — dépassement de plafond | ☐ OK ☐ KO | | |
| 4.6 | Reprise, 5 cycles | ☐ OK ☐ KO | | |
| 4.7 | Charge soutenue | ☐ OK ☐ KO | | |

---

## 5. Protocole de test conjoint avec le Groupe III

> Cette section est également **non exécutable aujourd'hui** : elle suppose un
> `CanDataSource` côté frontend et un firmware capable d'émettre sur SocketCAN
> côté Groupe III.

### 5.1 Pourquoi cette séance est représentative

L'énoncé décrit l'architecture réelle ainsi : « le firmware ouvre un socket
`AF_CAN` et y écrit ses trames ; l'application Qt ouvre un socket sur la même
interface et les lit ». Sur `vcan0`, **c'est littéralement ce qui se passe.**
Le seul écart avec le véhicule est l'absence de couche physique — donc, pour
tout ce qui concerne le format et le protocole, la séance est représentative à
100 %.

Ce n'est pas une simulation d'intégration : c'est l'intégration, moins les
fils.

### 5.2 Ce que chaque équipe apporte

**Groupe III (firmware) — sans quoi la séance n'a pas lieu :**

- [ ] Un binaire émettant sur une interface CAN **passée en paramètre**
      (`./vcu_sim vcan0`). Un nom d'interface codé en dur oblige à recompiler
      à chaque essai, et fera perdre la séance.
- [ ] Le **plan d'adressage réel** : identifiants, DLC, endianness, facteurs
      d'échelle, offsets, périodes. Un fichier DBC si l'outillage en produit un
      — sinon un tableau suffit.
- [ ] La réponse à la question ouverte n° 2 du §7 de
      [`interface-can.md`](interface-can.md) : **l'odomètre est-il sur le
      bus ?** C'est la seule question dont la réponse change l'architecture de
      `CanDataSource`, et non un simple paramètre.
- [ ] Un moyen de **provoquer une panne à la demande** : un signal, une touche,
      un argument. Les tests §4.2 et §4.4 en dépendent entièrement.
- [ ] Leur convention de compteur de séquence et de checksum, si elle existe
      déjà (question ouverte n° 5).

**Équipe frontend :**

- [ ] `src/CanDataSource.qml`, publiant les cinq propriétés du contrat, à jour
      du plan d'adressage reçu **avant** la séance. Découvrir le format le jour
      même garantit de passer la séance à coder au lieu de tester.
- [ ] Le décodeur du §3.4 adapté à ce plan d'adressage — c'est l'arbitre
      indépendant en cas de désaccord.
- [ ] Ce document et [`interface-can.md`](interface-can.md), imprimés ou
      ouverts.
- [ ] `qmllint` et `qmltestrunner` au vert avant la séance. On ne débogue pas
      une intégration sur une base déjà rouge.

**Matériel commun :** une machine Linux avec `vcan`. Une seule suffit.

### 5.3 Ordre des vérifications

L'ordre n'est pas indifférent : chaque étape ne suppose que les précédentes.
Une étape en échec **arrête la séance à ce niveau** — inutile de tester
l'affichage si les identifiants ne concordent pas.

**Étape 0 — accord sur le format, sans machine.** Comparer le plan d'adressage
du Groupe III aux tableaux du §3 de [`interface-can.md`](interface-can.md).
Relever tous les écarts par écrit. **Le format du Groupe III prime sans
discussion.** Si un écart est trouvé, corriger `interface-can.md` avant de
brancher quoi que ce soit.

**Étape 1 — le firmware émet, sans l'IHM.**

```sh
candump -L vcan0 > seance.log
```

- [ ] Les identifiants observés sont ceux annoncés.
- [ ] Les DLC sont ceux annoncés (`candump -ta` affiche `[8]`, `[4]`, `[2]`).
- [ ] Les périodes correspondent — mesurables sur les horodatages de la capture.
- [ ] Aucun identifiant inattendu ne circule.

Tester l'IHM avant cette étape ferait chercher côté affichage une erreur qui
est côté bus.

**Étape 2 — décodage hors ligne, arbitre neutre.**

```sh
python3 decode.py seance.log
```

- [ ] Les valeurs décodées correspondent à ce que le firmware croit émettre.
      **Le Groupe III doit confirmer les valeurs à voix haute** avant qu'on les
      lise : c'est le seul moment où l'on peut attraper un facteur d'échelle
      inversé sans ambiguïté sur le responsable.
- [ ] Les CRC, s'il y en a, sont corrects.
- [ ] Cas limites : demander 0, puis le plafond. Ce sont ceux qui révèlent les
      erreurs de signe et d'endianness (§3.2).

**Étape 3 — l'IHM lit, le firmware émet.** Les deux ensemble, enfin.

- [ ] Les valeurs affichées correspondent à celles du §étape 2.
- [ ] La rampe du §4.1, pilotée cette fois par le vrai firmware.

**Étape 4 — les cas de défaut.** §4.2, §4.4, §4.5, §4.6, avec le moyen de
provoquer une panne fourni par le Groupe III.

**Étape 5 — relevé.** Remplir le tableau du §4.8, consigner les écarts, et
**mettre à jour [`interface-can.md`](interface-can.md)** : à l'issue de cette
séance, ce document n'est plus une proposition mais une spécification convenue.
Son encadré de statut doit être réécrit en conséquence.

### 5.4 Deux pièges de séance

**Le firmware et l'IHM sur deux machines.** `vcan` est **strictement local** :
il n'y a aucun trafic réseau, deux machines ne partagent pas un `vcan0`. Si les
deux équipes doivent travailler à distance, il faut `cannelloni` ou un tunnel
équivalent — à préparer avant, pas le jour même.

**Le décodeur adapté à la hâte.** Si le décodeur du §3.4 est modifié pendant la
séance pour coller au format du Groupe III, il cesse d'être un arbitre
indépendant : il valide alors ce qu'on vient de lui apprendre. Le mettre à jour
depuis le **document** de spécification, jamais depuis les octets observés.

---

## 6. Limites de cette approche

Section volontairement explicite. Un test qui passe sur `vcan` autorise à
passer à l'étape suivante ; il n'autorise rien d'autre.

### 6.1 Ce que `vcan` ne teste pas

Détaillé au §1.3. En résumé : **toute la couche physique et tout le
comportement temps réel du bus.** Notamment, et c'est le plus gênant :

- **L'arbitrage.** La justification du choix des identifiants — priorité de
  `0x100` sur `0x300` et `0x500` — occupe une demi-page de
  [`interface-can.md`](interface-can.md) et **n'est vérifiée par aucun test de
  ce document.** Les trois identifiants pourraient être permutés sans qu'aucun
  critère de réussite ne bouge.
- **La saturation du bus.** L'estimation de 2,9 kbit/s reste un calcul sur le
  papier.
- **Les erreurs de trame et le `bus-off`.** Le comportement de l'IHM face à un
  contrôleur qui se met en `bus-off` est **entièrement non spécifié** — ni ici,
  ni dans `interface-can.md`. C'est un manque à combler avec le Groupe III.
- **Les seuils de chien de garde.** Trois périodes reposent sur une hypothèse de
  taux d'erreur. `vcan` ayant un taux de perte nul, il ne peut ni confirmer ni
  infirmer ce choix : il vérifie que le mécanisme se déclenche, pas que le seuil
  est bien réglé.

### 6.2 Ce qu'un adaptateur CAN réel apporterait

Un adaptateur USB-CAN et deux nœuds sur un segment terminé — quelques dizaines
d'euros — permettraient de tester, sans véhicule :

- l'arbitrage réel, en faisant émettre deux nœuds simultanément ;
- le débit et la charge de bus effectifs ;
- les compteurs d'erreur, le passage en `error-passive` puis `bus-off`, et la
  récupération ;
- la gigue réelle d'un contrôleur, donc le réglage du seuil de chien de garde ;
- le débranchement physique d'un connecteur, qui n'est pas la même chose qu'un
  processus tué — c'est le test du §4.2, en vrai.

C'est le chaînon manquant entre ce document et le véhicule, et il est **peu
coûteux**. La référence d'adaptateur est déjà une question ouverte (n° 4 du §7
de [`interface-can.md`](interface-can.md)) ; il vaudrait la peine d'en
commander un.

### 6.3 Ce que seul le véhicule permettrait

- La cohérence des grandeurs avec la réalité : le compteur indique-t-il la
  vitesse **réelle** de la navette ? Aucun test logiciel ne peut y répondre.
- Le comportement au démarrage et à la coupure du contact — question ouverte
  n° 6 du §7 de [`interface-can.md`](interface-can.md).
- Les perturbations électromagnétiques d'une chaîne de traction en charge.
- La température, les vibrations, la lisibilité de l'écran en plein soleil.
- L'ergonomie en conduite, qu'aucun banc ne remplace.

### 6.4 La performance — la limite la plus importante

**Aucun test de ce document ne dit quoi que ce soit sur la fluidité du rendu
sur Raspberry Pi 4.** C'est la limite à retenir en priorité, parce qu'elle est
la plus facile à oublier : les tests passent, l'affichage est fluide sur la
machine de développement, et l'on en conclut à tort que la cible suivra.

Or :

- Tout ce qui précède tourne sur une machine de développement dont le GPU et
  la bande passante mémoire n'ont **aucun rapport** avec ceux du Pi 4.
- Le compteur `--fps` relève la fréquence de l'écran de développement, pas la
  marge disponible sur la cible. C'est déjà consigné dans les limites connues
  du [`README.md`](../README.md).
- Le seuil de 55 FPS du §5 de [`DESIGN.md`](../DESIGN.md) **reste à vérifier
  sur matériel réel**.
- Le décodage CAN ajoutera une charge CPU — modeste, mais non nulle — qui n'est
  mesurée nulle part sur la cible.

La seule mesure qui vaille est `--fps` **sur le Pi 4 lui-même**, alimenté par
un `cangen` à la cadence nominale. Tant qu'elle n'a pas été faite, la fluidité
sur cible est une hypothèse, pas un résultat.

---

## Références

- [`docs/interface-can.md`](interface-can.md) — trames proposées, encodage
  octet par octet, détection de défaut, procédure de substitution. **C'est la
  source des valeurs vérifiées ici** ; en cas de divergence, c'est ce
  document-là qui fait foi.
- [`README.md`](../README.md) — contrat de données, architecture, lancement,
  limites connues.
- [`CONVENTIONS.md`](../CONVENTIONS.md) — périmètre du projet et règles de
  contribution.
- [`DESIGN.md`](../DESIGN.md) — langage visuel, seuil de performance.
- `man 8 ip-link`, `man 1 candump`, `man 1 cansend`, `man 1 cangen`.
- Documentation du noyau Linux : `Documentation/networking/can.rst`.
