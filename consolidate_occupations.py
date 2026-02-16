"""
Consolidate occupations/ files from ~154 down to ~25 thematic groups.

Run from the repo root:
    python3 consolidate_occupations.py [--dry-run]
"""

import os
import sys

BASE = "/Users/mjsuhonos/Documents/GitHub/wikicore/occupations"
DRY_RUN = "--dry-run" in sys.argv


def read_tsv(path):
    if not os.path.exists(path):
        return []
    with open(path, encoding="utf-8") as f:
        return [l.rstrip("\n") for l in f if l.strip()]


def append_to(dest_name, lines):
    if not lines:
        return
    dest_path = f"{BASE}/{dest_name}"
    if DRY_RUN:
        print(f"  [dry] would append {len(lines)} lines to {dest_name}")
        return
    with open(dest_path, "a", encoding="utf-8") as f:
        for line in lines:
            f.write(line + "\n")


def remove_file(name):
    path = f"{BASE}/{name}"
    if not os.path.exists(path):
        return
    if DRY_RUN:
        print(f"  [dry] would delete {name}")
        return
    os.remove(path)


def merge(sources, dest):
    """Append all lines from source files into dest, then delete sources."""
    total = 0
    for src in sources:
        lines = read_tsv(f"{BASE}/{src}")
        if lines:
            append_to(dest, lines)
            total += len(lines)
            remove_file(src)
    print(f"  {dest} ← merged {sources}  ({total} lines)")


# ---------------------------------------------------------------------------
# 1. other.tsv — move remaining 49 entries to appropriate files
# ---------------------------------------------------------------------------
print("\n=== 1. Drain other.tsv ===")

other_lines = read_tsv(f"{BASE}/other.tsv")
other_entries = {l.split("\t")[0]: l for l in other_lines}

other_mapping = {
    # politics
    "QQ82955":    "politics.tsv",   # politician
    "QQ212238":   "politics.tsv",   # civilservant
    "QQ80687":    "politics.tsv",   # secretary
    "QQ5784340":  "politics.tsv",   # consort
    "QQ11986654": "politics.tsv",   # lobbyist

    # law
    "QQ16533":    "law.tsv",        # judge
    "QQ384593":   "law.tsv",        # policeofficer
    "QQ8142883":  "law.tsv",        # criminologist

    # military
    "QQ11397897": "military.tsv",   # swordfighter

    # medicine
    "QQ774306":   "medicine.tsv",   # surgeon
    "QQ12765408": "medicine.tsv",   # epidemiologist
    "QQ12119633": "medicine.tsv",   # immunologist
    "QQ3410028":  "medicine.tsv",   # psychoanalyst

    # science
    "QQ201788":   "science.tsv",    # historian (scholarly, not pop-history)
    "QQ11631":    "science.tsv",    # astronaut
    "QQ3140857":  "science.tsv",    # horticulturist
    "QQ13416354": "science.tsv",    # mineralogist

    # engineering
    # (none left)

    # education
    "QQ7019111":  "education.tsv",  # socialworker
    "QQ2251335":  "education.tsv",  # schoolteacher

    # literature
    "QQ333634":   "literature.tsv", # translator
    "QQ18814623": "literature.tsv", # autobiographer
    "QQ1607826":  "literature.tsv", # editor

    # media
    # (none)

    # film
    "QQ3455803":  "film.tsv",       # director
    "QQ1162163":  "film.tsv",       # director (alt QID)
    "QQ1208175":  "film.tsv",       # cameraoperator
    "QQ935666":   "film.tsv",       # make_upartist

    # arts
    "QQ483501":   "arts.tsv",       # artist
    "QQ17505902": "arts.tsv",       # watercolorist
    "QQ2145981":  "arts.tsv",       # restorer
    "QQ175151":   "arts.tsv",       # printer (historical)
    "QQ12859263": "arts.tsv",       # orator

    # music
    "QQ12360214": "music.tsv",      # bassguitarist
    "QQ1327329":  "music.tsv",      # multi_instrumentalist
    "QQ2340668":  "music.tsv",      # musicvideo_director

    # sports
    "QQ17486376": "sports.tsv",     # sportshooter
    "QQ19841381": "sports.tsv",     # canadianfootball_player
    "QQ13381863": "sports.tsv",     # fencer
    "QQ15117395": "sports.tsv",     # trackcyclist
    "QQ13581129": "sports.tsv",     # orienteer
    "QQ13856320": "sports.tsv",     # hammerthrower
    "QQ12803959": "sports.tsv",     # runner
    "QQ17614049": "sports.tsv",     # nascarteam_owner

    # activism
    "QQ15627169": "activism.tsv",   # tradeunionist
    "QQ3409375":  "activism.tsv",   # anglicanpriest (religious activist context)

    # misc
    "QQ11900058": "misc.tsv",       # explorer
    "QQ188784":   "misc.tsv",       # superhero
    "QQ155647":   "misc.tsv",       # astrologer
    "QQ12356615": "misc.tsv",       # traveler
    "QQ107711":   "misc.tsv",       # firefighter
}

# Group moves by destination
other_by_dest = {}
moved = set()
for qid, dest in other_mapping.items():
    if qid in other_entries:
        other_by_dest.setdefault(dest, []).append(other_entries[qid])
        moved.add(qid)

for dest, lines in sorted(other_by_dest.items()):
    append_to(dest, lines)
    print(f"  other.tsv → {dest}  ({len(lines)} entries)")

# Rewrite other.tsv with only what remains
remaining = [l for l in other_lines if l.split("\t")[0] not in moved]
if not DRY_RUN:
    with open(f"{BASE}/other.tsv", "w", encoding="utf-8") as f:
        for line in remaining:
            f.write(line + "\n")
print(f"  other.tsv: {len(moved)} moved, {len(remaining)} remaining")


# ---------------------------------------------------------------------------
# 2. Sports — absorb all sport-specific files into sports.tsv
# ---------------------------------------------------------------------------
print("\n=== 2. Sports consolidation ===")
merge([
    "americanfootball.tsv",
    "associationfootball.tsv",
    "australianrules.tsv",
    "icehockey.tsv",
    "rugbyleague.tsv",
    "rugbysevens.tsv",
    "rugbyunion.tsv",
    "fieldhockey.tsv",
    "figureskating.tsv",
    "mixedmartial.tsv",
    "professionalwrestling.tsv",
    "waterpolo.tsv",
    "cross.tsv",       # cross-country skiing
    "pes.tsv",         # Finnish baseball (pesäpallo)
], "sports.tsv")


# ---------------------------------------------------------------------------
# 3. Religion — absorb related files into religion.tsv
# ---------------------------------------------------------------------------
print("\n=== 3. Religion consolidation ===")
merge([
    "latincatholic.tsv",
    "easternorthodox.tsv",
    "romancatholic.tsv",
    "anglicanbishop.tsv",
    "highpriest.tsv",
    "bishopof.tsv",
    "archdeaconof.tsv",
    "deanof.tsv",
    "patriarchof.tsv",
    "ancientroman.tsv",  # Roman priests & senators
    "religious.tsv",
], "religion.tsv")


# ---------------------------------------------------------------------------
# 4. Politics — absorb government-role files into politics.tsv
# ---------------------------------------------------------------------------
print("\n=== 4. Politics consolidation ===")
merge([
    "mayorof.tsv",
    "governorof.tsv",
    "presidentof.tsv",
    "primeminister.tsv",
    "vicepresident.tsv",
    "vice.tsv",
    "ministerof.tsv",
    "secretaryof.tsv",
    "secretarygeneral.tsv",
    "commissionerof.tsv",
    "chairmanof.tsv",
    "headof.tsv",
    "chiefof.tsv",
    "prefectof.tsv",
    "regentof.tsv",
    "ambassadorof.tsv",
    "princeof.tsv",
    "lordmayor.tsv",
    "king.tsv",
    "kingof.tsv",
    "countof.tsv",
    "dukeof.tsv",
    "emirof.tsv",
    "prince.tsv",
    "royalconsort.tsv",
    "queenconsort.tsv",
    "firstlady.tsv",
    "lady.tsv",
    "civilservant.tsv",
    "people.tsv",
    "whitehouse.tsv",
    "unitednations.tsv",
    "boardof.tsv",
    "associatejustice.tsv",
    "memberof.tsv",
], "politics.tsv")


# ---------------------------------------------------------------------------
# 5. Military — absorb related files
# ---------------------------------------------------------------------------
print("\n=== 5. Military consolidation ===")
merge([
    "officerof.tsv",
    "commander.tsv",
    "inspectorgeneral.tsv",
    "sub.tsv",
    "serjeant.tsv",
    "knight.tsv",
], "military.tsv")

# unitedstates has a mix of military, diplomatic, and generic gov.
# Absorb into military (mostly military branches/roles)
merge(["unitedstates.tsv"], "military.tsv")


# ---------------------------------------------------------------------------
# 6. Law — absorb related files
# ---------------------------------------------------------------------------
print("\n=== 6. Law consolidation ===")
merge([
    "judgeof.tsv",
    "judge.tsv",
    "attorney.tsv",
    "highcourt.tsv",
    "chiefjustice.tsv",
    "commissioner.tsv",
], "law.tsv")


# ---------------------------------------------------------------------------
# 7. Education — absorb "of" files and related
# ---------------------------------------------------------------------------
print("\n=== 7. Education consolidation ===")
merge([
    "scholarof.tsv",
    "professorof.tsv",
    "masterof.tsv",
    "teacherof.tsv",
    "universityof.tsv",
    "philosopherof.tsv",
    "professor.tsv",
    "scholar.tsv",
    "schoolteacher.tsv",
    "socialwork.tsv",
], "education.tsv")


# ---------------------------------------------------------------------------
# 8. Science — absorb related files
# ---------------------------------------------------------------------------
print("\n=== 8. Science consolidation ===")
merge([
    "discovererof.tsv",
    "historianof.tsv",   # historian of specific disciplines
], "science.tsv")


# ---------------------------------------------------------------------------
# 9. Film/TV — absorb entertainment-related files
# ---------------------------------------------------------------------------
print("\n=== 9. Film consolidation ===")
merge([
    "realitytelevision.tsv",
    "specialeffects.tsv",
    "visualeffects.tsv",
    "director.tsv",
    "editor.tsv",
], "film.tsv")


# ---------------------------------------------------------------------------
# 10. Media — absorb related files
# ---------------------------------------------------------------------------
print("\n=== 10. Media consolidation ===")
merge([
    "socialmedia.tsv",
    "publicrelations.tsv",
], "media.tsv")


# ---------------------------------------------------------------------------
# 11. Literature — absorb genre/craft files
# ---------------------------------------------------------------------------
print("\n=== 11. Literature consolidation ===")
merge([
    "sciencefiction.tsv",
    "speculativefiction.tsv",
    "german.tsv",          # German-X translators
    "translator.tsv",
], "literature.tsv")


# ---------------------------------------------------------------------------
# 12. Music — absorb singer (singer-songwriter is music)
# ---------------------------------------------------------------------------
print("\n=== 12. Music consolidation ===")
merge([
    "singer.tsv",
], "music.tsv")


# ---------------------------------------------------------------------------
# 13. Medicine — absorb health-related files
# ---------------------------------------------------------------------------
print("\n=== 13. Medicine consolidation ===")
merge([
    "mentalhealth.tsv",
    "publichealth.tsv",
    "surgeon.tsv",
    "doctorof.tsv",
], "medicine.tsv")


# ---------------------------------------------------------------------------
# 14. Engineering — absorb tech/computing files
# ---------------------------------------------------------------------------
print("\n=== 14. Engineering consolidation ===")
merge([
    "computerscience.tsv",
    "computersecurity.tsv",
    "printer.tsv",   # printer's devil — historical technical trade
], "engineering.tsv")


# ---------------------------------------------------------------------------
# 15. Business — absorb commerce/management files
# ---------------------------------------------------------------------------
print("\n=== 15. Business consolidation ===")
merge([
    "realestate.tsv",
    "chiefexecutive.tsv",
    "generalmanager.tsv",
    "chefde.tsv",
    "agent.tsv",
    "foreman.tsv",
    "domesticworker.tsv",
    "customerservice.tsv",
], "business.tsv")


# ---------------------------------------------------------------------------
# 16. Activism — absorb related files
# ---------------------------------------------------------------------------
print("\n=== 16. Activism consolidation ===")
merge([
    "anti.tsv",
    "humanrights.tsv",
    "women.tsv",
], "activism.tsv")


# ---------------------------------------------------------------------------
# 17. Arts — absorb related files
# ---------------------------------------------------------------------------
print("\n=== 17. Arts consolidation ===")
merge([
    "artist.tsv",
], "arts.tsv")


# ---------------------------------------------------------------------------
# 18. Film/media — extra files
# ---------------------------------------------------------------------------
print("\n=== 18. Film/media extra ===")
merge([
    "beautypageant.tsv",   # beauty pageant contestant/winner → entertainment
], "film.tsv")

merge([
    "videogame.tsv",       # video game roles → technology/entertainment
], "misc.tsv")


# ---------------------------------------------------------------------------
# 19. Literature — children's writing
# ---------------------------------------------------------------------------
print("\n=== 19. Literature extra ===")
merge([
    "children.tsv",        # children's writer, illustrator, entertainer
], "literature.tsv")


# ---------------------------------------------------------------------------
# 20. Science — history of science etc.
# ---------------------------------------------------------------------------
print("\n=== 20. Science extra ===")
merge([
    "historyof.tsv",       # history of science, history of Russia, etc.
], "science.tsv")


# ---------------------------------------------------------------------------
# 21. Education — master's student, notary, etc.
# ---------------------------------------------------------------------------
print("\n=== 21. Education/misc extra ===")
merge([
    "notary.tsv",          # notary's clerk etc. → law adjacent
], "law.tsv")

merge([
    "master.tsv",          # master's student → education
], "education.tsv")


# ---------------------------------------------------------------------------
# 22. Politics — ministry, state roles
# ---------------------------------------------------------------------------
print("\n=== 22. Politics extra ===")
merge([
    "ministryof.tsv",      # ministry of finance etc.
    "state.tsv",           # state attorney, state engineers
    "employeeof.tsv",      # employee of public institution
], "politics.tsv")


# ---------------------------------------------------------------------------
# 23. Misc — absorb truly miscellaneous tiny files
# ---------------------------------------------------------------------------
print("\n=== 23. Misc consolidation ===")
merge([
    "pok.tsv",           # Pokémon fictional roles
    "self.tsv",          # self-employed etc.
    "non.tsv",           # non-fiction writer, non-commissioned officer, etc.
    "magician.tsv",
    "official.tsv",
    "alcalde.tsv",
    "directorof.tsv",    # director of research/comms/etc — too diverse
    "secretary.tsv",
    "governor.tsv",
    "listof.tsv",
], "misc.tsv")


# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
print("\n=== Summary ===")
remaining_files = sorted(f for f in os.listdir(BASE) if f.endswith(".tsv"))
print(f"Files remaining: {len(remaining_files)}")
for fname in remaining_files:
    n = len(read_tsv(f"{BASE}/{fname}"))
    print(f"  {fname:40s} {n:4d} lines")
