import os

BASE = "/Users/mjsuhonos/Documents/GitHub/wikicore/working.nosync/p106_groups"

# Read other.tsv
with open(f"{BASE}/other.tsv") as f:
    lines = [l.rstrip('\n') for l in f if l.strip()]

# Build dict of qid -> line
entries = {}
for line in lines:
    qid = line.split('\t')[0]
    entries[qid] = line

# Mapping: qid -> destination filename (no path)
mapping = {
    # --- politics.tsv ---
    "QQ82955":   "politics.tsv",  # politician
    "QQ193391":  "politics.tsv",  # diplomat
    "QQ372436":  "politics.tsv",  # statesperson
    "QQ2304859": "politics.tsv",  # sovereign
    "QQ116":     "politics.tsv",  # monarch
    "QQ1097498": "politics.tsv",  # ruler
    "QQ12097":   "politics.tsv",  # king
    "QQ121998":  "politics.tsv",  # ambassador
    "QQ2478141": "politics.tsv",  # aristocrat
    "QQ11573099":"politics.tsv",  # royalty
    "QQ3242115": "politics.tsv",  # revolutionary
    "QQ49476":   "politics.tsv",  # archbishop (also religion — politics wins for state figures)
    "QQ477406":  "politics.tsv",  # regent
    "QQ30185":   "politics.tsv",  # mayor
    "QQ132050":  "politics.tsv",  # governor
    "QQ708492":  "politics.tsv",  # councilmember
    "QQ10547393":"politics.tsv",  # localpolitician
    "QQ8125919": "politics.tsv",  # politicaladviser
    "QQ1238570": "politics.tsv",  # politicalscientist
    "QQ140686":  "politics.tsv",  # chairperson
    "QQ4376769": "politics.tsv",  # universitypresident
    "QQ4479442": "politics.tsv",  # founder
    "QQ273108":  "politics.tsv",  # condottiero
    "QQ1409420": "politics.tsv",  # feudatory
    "QQ1259323": "politics.tsv",  # traditional_leader_or_chief
    "QQ17765219":"politics.tsv",  # colonial_administrator
    "QQ600751":  "politics.tsv",  # prosecutor
    "QQ725440":  "politics.tsv",  # prelate

    # --- military.tsv ---
    "QQ47064":   "military.tsv",  # militarypersonnel
    "QQ189290":  "military.tsv",  # militaryofficer
    "QQ1402561": "military.tsv",  # militaryleader
    "QQ11545923":"military.tsv",  # militarycommander
    "QQ10669499":"military.tsv",  # navalofficer
    "QQ38239859":"military.tsv",  # armyofficer
    "QQ4991371": "military.tsv",  # soldier
    "QQ9352089": "military.tsv",  # spy
    "QQ618694":  "military.tsv",  # fighterpilot
    "QQ222982":  "military.tsv",  # flyingace
    "QQ2095549": "military.tsv",  # aircraftpilot
    "QQ1250916": "military.tsv",  # warrior
    "QQ178197":  "military.tsv",  # mercenary
    "QQ164236":  "military.tsv",  # warcorrespondent
    "QQ201559":  "military.tsv",  # privateer
    "QQ10729326":"military.tsv",  # pirate
    "QQ3492027": "military.tsv",  # submariner
    "QQ151197":  "military.tsv",  # militaryengineer
    "QQ4002666": "military.tsv",  # militaryphysician
    "QQ10497074":"military.tsv",  # militaryflight_engineer
    "QQ1493121": "military.tsv",  # militaryhistorian
    "QQ46961":   "military.tsv",  # gangster
    "QQ730242":  "military.tsv",  # testpilot
    "QQ5121444": "military.tsv",  # intelligenceofficer

    # --- activism.tsv ---
    "QQ15253558":"activism.tsv",  # activist
    "QQ1397808": "activism.tsv",  # resistancefighter
    "QQ27532437":"activism.tsv",  # suffragist
    "QQ322170":  "activism.tsv",  # suffragette
    "QQ18510179":"activism.tsv",  # abolitionist
    "QQ16323111":"activism.tsv",  # peaceactivist
    "QQ19509201":"activism.tsv",  # lgbtiq_rights_activist
    "QQ11499147":"activism.tsv",  # politicalactivist
    "QQ8359428": "activism.tsv",  # socialactivist
    "QQ1021386": "activism.tsv",  # civilrights_advocate
    "QQ3578589": "activism.tsv",  # environmentalist
    "QQ16060693":"activism.tsv",  # conservationist
    "QQ61048378":"activism.tsv",  # climateactivist
    "QQ30242234":"activism.tsv",  # freedomfighter
    "QQ212948":  "activism.tsv",  # partisan
    "QQ23833535":"activism.tsv",  # french_resistance_fighter

    # --- law.tsv ---
    "QQ40348":   "law.tsv",  # lawyer
    "QQ185351":  "law.tsv",  # jurist
    "QQ808967":  "law.tsv",  # barrister
    "QQ14284":   "law.tsv",  # solicitor
    "QQ380075":  "law.tsv",  # advocate
    "QQ1209498": "law.tsv",  # poetlawyer
    "QQ4594605": "law.tsv",  # magistrate
    "QQ16012028":"law.tsv",  # legalscholar
    "QQ63677188":"law.tsv",  # lawprofessor
    "QQ12414919":"law.tsv",  # terrorist (legal system)
    "QQ2159907": "law.tsv",  # criminal
    "QQ931260":  "law.tsv",  # murderer
    "QQ484188":  "law.tsv",  # serialkiller
    "QQ10384029":"law.tsv",  # drugtrafficker
    "QQ12359071":"law.tsv",  # anarchist
    "QQ189010":  "law.tsv",  # notary

    # --- medicine.tsv ---
    "QQ39631":   "medicine.tsv",  # physician
    "QQ211346":  "medicine.tsv",  # psychiatrist
    "QQ212980":  "medicine.tsv",  # psychologist
    "QQ783906":  "medicine.tsv",  # neurologist
    "QQ3264451": "medicine.tsv",  # cardiologist
    "QQ2447386": "medicine.tsv",  # dermatologist
    "QQ16062369":"medicine.tsv",  # oncologist
    "QQ12013238":"medicine.tsv",  # ophthalmologist
    "QQ1919436": "medicine.tsv",  # paediatrician
    "QQ2640827": "medicine.tsv",  # gynaecologist
    "QQ13638192":"medicine.tsv",  # obstetrician
    "QQ15924224":"medicine.tsv",  # internist
    "QQ18245236":"medicine.tsv",  # radiologist
    "QQ2055046": "medicine.tsv",  # physiologist
    "QQ10872101":"medicine.tsv",  # anatomist
    "QQ3368718": "medicine.tsv",  # pathologist
    "QQ9385011": "medicine.tsv",  # neurosurgeon
    "QQ186360":  "medicine.tsv",  # nurse
    "QQ185196":  "medicine.tsv",  # midwife
    "QQ27349":   "medicine.tsv",  # dentist
    "QQ202883":  "medicine.tsv",  # veterinarian
    "QQ2576499": "medicine.tsv",  # nutritionist
    "QQ1900167": "medicine.tsv",  # psychotherapist
    "QQ105186":  "medicine.tsv",  # pharmacist
    "QQ2114605": "medicine.tsv",  # pharmacologist
    "QQ15401884":"medicine.tsv",  # medicalresearcher
    "QQ15143191":"medicine.tsv",  # sciencecommunicator
    "QQ551835":  "medicine.tsv",  # physicianwriter

    # --- science.tsv ---
    "QQ901":     "science.tsv",  # scientist
    "QQ169470":  "science.tsv",  # physicist
    "QQ593644":  "science.tsv",  # chemist
    "QQ170790":  "science.tsv",  # mathematician
    "QQ82594":   "science.tsv",  # computerscientist
    "QQ11063":   "science.tsv",  # astronomer
    "QQ752129":  "science.tsv",  # astrophysicist
    "QQ16742096":"science.tsv",  # nuclearphysicist
    "QQ19350898":"science.tsv",  # theoreticalphysicist
    "QQ864503":  "science.tsv",  # biologist
    "QQ2374149": "science.tsv",  # botanist
    "QQ350979":  "science.tsv",  # zoologist
    "QQ1225716": "science.tsv",  # ornithologist
    "QQ3055126": "science.tsv",  # entomologist
    "QQ497294":  "science.tsv",  # lepidopterist
    "QQ2487799": "science.tsv",  # mycologist
    "QQ4205432": "science.tsv",  # ichthyologist
    "QQ16271261":"science.tsv",  # malacologist
    "QQ16271064":"science.tsv",  # herpetologist
    "QQ3640160": "science.tsv",  # marinebiologist
    "QQ3779582": "science.tsv",  # microbiologist
    "QQ15816836":"science.tsv",  # bacteriologist
    "QQ15634281":"science.tsv",  # virologist
    "QQ3126128": "science.tsv",  # geneticist
    "QQ15839206":"science.tsv",  # molecularbiologist
    "QQ2919046": "science.tsv",  # biochemist
    "QQ14906342":"science.tsv",  # biophysicist
    "QQ6337803": "science.tsv",  # neuroscientist
    "QQ520549":  "science.tsv",  # geologist
    "QQ901402":  "science.tsv",  # geographer
    "QQ12094958":"science.tsv",  # geophysicist
    "QQ2732142": "science.tsv",  # statistician
    "QQ1650915": "science.tsv",  # researcher
    "QQ3400985": "science.tsv",  # academic
    "QQ188094":  "science.tsv",  # economist
    "QQ2306091": "science.tsv",  # sociologist
    "QQ4773904": "science.tsv",  # anthropologist
    "QQ1662561": "science.tsv",  # palaeontologist
    "QQ3621491": "science.tsv",  # archaeologist
    "QQ15983985":"science.tsv",  # classicalarchaeologist
    "QQ17488316":"science.tsv",  # prehistorian
    "QQ1371378": "science.tsv",  # ethnologist
    "QQ12347522":"science.tsv",  # ethnographer
    "QQ17484288":"science.tsv",  # ethnomusicologist
    "QQ4964182": "science.tsv",  # philosopher
    "QQ15442776":"science.tsv",  # cryptographer
    "QQ2468727": "science.tsv",  # classicalscholar
    "QQ16267607":"science.tsv",  # classicalphilologist
    "QQ13418253":"science.tsv",  # philologist
    "QQ14467526":"science.tsv",  # linguist
    "QQ1731155": "science.tsv",  # orientalist
    "QQ3155377": "science.tsv",  # islamicist
    "QQ18524037":"science.tsv",  # indologist
    "QQ2599593": "science.tsv",  # germanist
    "QQ2504617": "science.tsv",  # romanist
    "QQ15255771":"science.tsv",  # sinologist
    "QQ16308156":"science.tsv",  # anglicist
    "QQ98544732":"science.tsv",  # scientificcollector
    "QQ19507792":"science.tsv",  # scientificillustrator
    "QQ2083925": "science.tsv",  # botanicalcollector
    "QQ109120509":"science.tsv", # zoologicalcollector
    "QQ1781198": "science.tsv",  # agronomist
    "QQ18805":   "science.tsv",  # naturalist
    "QQ15976092":"science.tsv",  # artificialintelligence_researcher
    "QQ1113838": "science.tsv",  # climatologist
    "QQ15839134":"science.tsv",  # ecologist
    "QQ3546255": "science.tsv",  # oceanographer
    "QQ2310145": "science.tsv",  # meteorologist

    # --- engineering.tsv ---
    "QQ81096":   "engineering.tsv",  # engineer
    "QQ1326886": "engineering.tsv",  # electricalengineer
    "QQ13582652":"engineering.tsv",  # civilengineer
    "QQ1906857": "engineering.tsv",  # mechanicalengineer
    "QQ7888586": "engineering.tsv",  # chemicalengineer
    "QQ42973":   "engineering.tsv",  # architect
    "QQ11295636":"engineering.tsv",  # cardesigner
    "QQ2815948": "engineering.tsv",  # landscapearchitect
    "QQ14623005":"engineering.tsv",  # architecturaldraftsperson
    "QQ11486702":"engineering.tsv",  # architecturalhistorian
    "QQ131062":  "engineering.tsv",  # urbanplanner
    "QQ5482740": "engineering.tsv",  # programmer
    "QQ18576582":"engineering.tsv",  # metallurgist
    "QQ18524075":"engineering.tsv",  # miningengineer
    "QQ1734662": "engineering.tsv",  # cartographer
    "QQ294126":  "engineering.tsv",  # landsurveyor
    "QQ205375":  "engineering.tsv",  # inventor
    "QQ11085831":"engineering.tsv",  # interpreter

    # --- education.tsv ---
    "QQ1622272": "education.tsv",  # universityteacher
    "QQ37226":   "education.tsv",  # teacher
    "QQ121594":  "education.tsv",  # professor (also professor.tsv — new entries here)
    "QQ974144":  "education.tsv",  # educator
    "QQ1231865": "education.tsv",  # educationist
    "QQ1056391": "education.tsv",  # headteacher
    "QQ182436":  "education.tsv",  # librarian
    "QQ462390":  "education.tsv",  # docent
    "QQ1569495": "education.tsv",  # lecturer
    "QQ9379869": "education.tsv",  # lecturer (alt)
    "QQ2449921": "education.tsv",  # dramateacher
    "QQ2675537": "education.tsv",  # musicteacher
    "QQ16145150":"education.tsv",  # musiceducator
    "QQ5758653": "education.tsv",  # secondaryschool_teacher
    "QQ21281706":"education.tsv",  # academicadministrator
    "QQ48072011":"education.tsv",  # businesstheorist
    "QQ15319501":"education.tsv",  # socialscientist
    "QQ10333969":"education.tsv",  # museologist
    "QQ635734":  "education.tsv",  # archivist
    "QQ48282":   "education.tsv",  # student

    # --- religion.tsv ---
    "QQ250867":  "religion.tsv",  # catholicpriest
    "QQ611644":  "religion.tsv",  # catholicbishop
    "QQ83307":   "religion.tsv",  # minister
    "QQ42603":   "religion.tsv",  # priest
    "QQ152002":  "religion.tsv",  # pastor
    "QQ831474":  "religion.tsv",  # presbyter
    "QQ733786":  "religion.tsv",  # monk
    "QQ191808":  "religion.tsv",  # nun
    "QQ548320":  "religion.tsv",  # friar
    "QQ133485":  "religion.tsv",  # rabbi
    "QQ125482":  "religion.tsv",  # imam
    "QQ3315492": "religion.tsv",  # clergyman
    "QQ2259532": "religion.tsv",  # cleric
    "QQ161944":  "religion.tsv",  # deacon
    "QQ193364":  "religion.tsv",  # vicar
    "QQ1753370": "religion.tsv",  # curate
    "QQ1104153": "religion.tsv",  # canon
    "QQ432386":  "religion.tsv",  # preacher
    "QQ208762":  "religion.tsv",  # chaplain
    "QQ219477":  "religion.tsv",  # missionary
    "QQ189459":  "religion.tsv",  # ulama
    "QQ1172458": "religion.tsv",  # muhaddith
    "QQ1999841": "religion.tsv",  # islamicjurist
    "QQ1423891": "religion.tsv",  # christianminister
    "QQ25393460":"religion.tsv",  # catholicdeacon
    "QQ3146899": "religion.tsv",  # diocese (P106 for religious admin)
    "QQ96236305":"religion.tsv",  # lutheranpastor
    "QQ98833890":"religion.tsv",  # catholictheologian
    "QQ1234713": "religion.tsv",  # theologian
    "QQ1743122": "religion.tsv",  # churchhistorian
    "QQ13424456":"religion.tsv",  # hymnwriter
    "QQ19829980":"religion.tsv",  # religiousstudies_scholar
    "QQ19829990":"religion.tsv",  # biblicalscholar
    "QQ24262584":"religion.tsv",  # bibletranslator
    "QQ15995642":"religion.tsv",  # religiousleader
    "QQ4504549": "religion.tsv",  # religiousfigure
    "QQ2566598": "religion.tsv",  # religious
    "QQ854997":  "religion.tsv",  # bhikkhu
    "QQ38142":   "religion.tsv",  # samurai (Bushido/warrior-monk tradition)

    # --- literature.tsv ---
    "QQ36180":   "literature.tsv",  # writer
    "QQ482980":  "literature.tsv",  # author
    "QQ6625963": "literature.tsv",  # novelist
    "QQ49757":   "literature.tsv",  # poet
    "QQ214917":  "literature.tsv",  # playwright
    "QQ11774202":"literature.tsv",  # essayist
    "QQ15949613":"literature.tsv",  # shortstory_writer
    "QQ12144794":"literature.tsv",  # prosewriter
    "QQ11774156":"literature.tsv",  # memoirist
    "QQ18612623":"literature.tsv",  # autobiographer
    "QQ18939491":"literature.tsv",  # diarist
    "QQ12406482":"literature.tsv",  # humorist
    "QQ4263842": "literature.tsv",  # literarycritic
    "QQ17167049":"literature.tsv",  # literaryscholar
    "QQ13570226":"literature.tsv",  # literaryhistorian
    "QQ15962340":"literature.tsv",  # literarytheorist
    "QQ6673651": "literature.tsv",  # literaryscholar (alt)
    "QQ3332711": "literature.tsv",  # medievalist
    "QQ8178443": "literature.tsv",  # librettist
    "QQ1086863": "literature.tsv",  # columnist
    "QQ11499929":"literature.tsv",  # manof_letters
    "QQ27431213":"literature.tsv",  # cookbookwriter
    "QQ10297252":"literature.tsv",  # crimefiction_writer
    "QQ3075052": "literature.tsv",  # folklorist
    "QQ14972848":"literature.tsv",  # lexicographer
    "QQ15991187":"literature.tsv",  # grammarian
    "QQ17337766":"literature.tsv",  # theatrecritic
    "QQ6430706": "literature.tsv",  # critic
    "QQ4164507": "literature.tsv",  # artcritic
    "QQ4220892": "literature.tsv",  # filmcritic
    "QQ1350157": "literature.tsv",  # musiccritic
    "QQ1350189": "literature.tsv",  # egyptologist
    "QQ1792450": "literature.tsv",  # arthistorian
    "QQ17391638":"literature.tsv",  # arttheorist
    "QQ20198542":"literature.tsv",  # musichistorian
    "QQ16031530":"literature.tsv",  # musictheorist
    "QQ20826540":"literature.tsv",  # scholar
    "QQ3330547": "literature.tsv",  # chronicler
    "QQ860918":  "literature.tsv",  # esperantist

    # --- media.tsv ---
    "QQ1930187": "media.tsv",  # journalist
    "QQ42909":   "media.tsv",  # journalist (alt)
    "QQ6051619": "media.tsv",  # opinionjournalist
    "QQ11313148":"media.tsv",  # sportsjournalist
    "QQ20669622":"media.tsv",  # musicjournalist
    "QQ957729":  "media.tsv",  # photojournalist
    "QQ876864":  "media.tsv",  # editingstaff
    "QQ2986228": "media.tsv",  # sportscommentator
    "QQ599151":  "media.tsv",  # official
    "QQ270389":  "media.tsv",  # newspresenter
    "QQ13590141":"media.tsv",  # presenter
    "QQ947873":  "media.tsv",  # televisionpresenter
    "QQ1371925": "media.tsv",  # announcer
    "QQ2722764": "media.tsv",  # radiopersonality
    "QQ130857":  "media.tsv",  # discjockey
    "QQ15077007":"media.tsv",  # podcaster
    "QQ8246794": "media.tsv",  # blogger
    "QQ17125263":"media.tsv",  # youtuber
    "QQ4110598": "media.tsv",  # vlogger
    "QQ2045208": "media.tsv",  # internetcelebrity
    "QQ135301631":"media.tsv", # broadcaster
    "QQ17351648":"media.tsv",  # newspapereditor
    "QQ1155838": "media.tsv",  # correspondent
    "QQ15313492":"media.tsv",  # socialscientist (no — that's education)

    # --- film.tsv ---
    "QQ33999":   "film.tsv",   # actor
    "QQ10800557":"film.tsv",   # filmactor
    "QQ10798782":"film.tsv",   # televisionactor
    "QQ2259451": "film.tsv",   # stageactor
    "QQ2405480": "film.tsv",   # voiceactor
    "QQ11481802":"film.tsv",   # dubactor
    "QQ970153":  "film.tsv",   # childactor
    "QQ948329":  "film.tsv",   # characteractor
    "QQ2526255": "film.tsv",   # filmdirector
    "QQ2059704": "film.tsv",   # televisiondirector
    "QQ3387717": "film.tsv",   # theatredirector
    "QQ28389":   "film.tsv",   # screenwriter
    "QQ69423232":"film.tsv",   # filmscreenwriter
    "QQ73306227":"film.tsv",   # televisionwriter
    "QQ3282637": "film.tsv",   # filmproducer
    "QQ578109":  "film.tsv",   # televisionproducer
    "QQ1053574": "film.tsv",   # executiveproducer
    "QQ47541952":"film.tsv",   # producer
    "QQ222344":  "film.tsv",   # cinematographer
    "QQ7042855": "film.tsv",   # filmeditor
    "QQ1414443": "film.tsv",   # filmmaker
    "QQ1235146": "film.tsv",   # documentaryfilmmaker
    "QQ11814411":"film.tsv",   # documentarian
    "QQ465501":  "film.tsv",   # stuntperformer
    "QQ1208373": "film.tsv",   # cameraoperator
    "QQ2962070": "film.tsv",   # productiondesigner
    "QQ1049296": "film.tsv",   # castingdirector
    "QQ1323191": "film.tsv",   # costumedesigner
    "QQ2707485": "film.tsv",   # scenographer
    "QQ706364":  "film.tsv",   # artdirector
    "QQ44508716":"film.tsv",   # televisionpersonality
    "QQ488111":  "film.tsv",   # adultfilm_actor
    "QQ245068":  "film.tsv",   # comedian
    "QQ18545066":"film.tsv",   # stand_upcomedian
    "QQ10774753":"film.tsv",   # performanceartist
    "QQ15214752":"film.tsv",   # cabaretperformer
    "QQ713200":  "film.tsv",   # performingartist
    "QQ138858":  "film.tsv",   # entertainer
    "QQ5716684": "film.tsv",   # dancer
    "QQ805221":  "film.tsv",   # balletdancer
    "QQ2490358": "film.tsv",   # choreographer
    "QQ1440873": "film.tsv",   # showrunner
    "QQ2705098": "film.tsv",   # tarento
    "QQ1642960": "film.tsv",   # pundit

    # --- music.tsv ---
    "QQ177220":  "music.tsv",  # singer (QQ — same as singer.tsv entry; goes to music)
    "QQ36834":   "music.tsv",  # composer
    "QQ639669":  "music.tsv",  # musician
    "QQ158852":  "music.tsv",  # conductor
    "QQ183945":  "music.tsv",  # recordproducer
    "QQ753110":  "music.tsv",  # songwriter
    "QQ822146":  "music.tsv",  # lyricist
    "QQ15981151":"music.tsv",  # jazzmusician
    "QQ2865819": "music.tsv",  # operasinger
    "QQ486748":  "music.tsv",  # pianist
    "QQ855091":  "music.tsv",  # guitarist
    "QQ584301":  "music.tsv",  # bassist
    "QQ386854":  "music.tsv",  # drummer
    "QQ765778":  "music.tsv",  # organist
    "QQ13219637":"music.tsv",  # cellist
    "QQ1259917": "music.tsv",  # violinist
    "QQ899758":  "music.tsv",  # violist
    "QQ16003954":"music.tsv",  # oboist
    "QQ118865":  "music.tsv",  # clarinetist
    "QQ12377274":"music.tsv",  # trumpeter
    "QQ5371902": "music.tsv",  # harpsichordist
    "QQ21166956":"music.tsv",  # lutenist
    "QQ12902372":"music.tsv",  # flautist
    "QQ4351403": "music.tsv",  # percussionist
    "QQ12800682":"music.tsv",  # saxophonist
    "QQ19723482":"music.tsv",  # mandolinist
    "QQ1075651": "music.tsv",  # keyboardist
    "QQ9648008": "music.tsv",  # banjoist
    "QQ3560496": "music.tsv",  # fiddler
    "QQ6168364": "music.tsv",  # jazzguitarist
    "QQ61996187":"music.tsv",  # classicalpianist
    "QQ24067349":"music.tsv",  # classicalguitarist
    "QQ21680663":"music.tsv",  # classicalcomposer
    "QQ1643514": "music.tsv",  # musicarranger
    "QQ1076502": "music.tsv",  # choirdirector
    "QQ806349":  "music.tsv",  # bandleader
    "QQ1415090": "music.tsv",  # filmscore_composer
    "QQ3922505": "music.tsv",  # djproducer
    "QQ55960555":"music.tsv",  # recordingartist
    "QQ2643890": "music.tsv",  # vocalist
    "QQ2252262": "music.tsv",  # rapper
    "QQ1198887": "music.tsv",  # musicdirector
    "QQ14915627":"music.tsv",  # musicologist
    # QQ8963721 genealogist → genealogy.tsv (assigned below)
    "QQ131186":  "music.tsv",  # choir (already in music)
    "QQ1955150": "music.tsv",  # musicalinstrument_maker
    "QQ128124":  "music.tsv",  # audioengineer
    "QQ186370":  "music.tsv",  # troubadour
    "QQ3089940": "music.tsv",  # musicexecutive
    "QQ3406651": "music.tsv",  # radioproducer
    "QQ622807":  "music.tsv",  # seiy_u016b (voice actor — Japan)

    # --- arts.tsv (visual arts) ---
    "QQ1028181": "arts.tsv",   # painter
    "QQ1281618": "arts.tsv",   # sculptor
    "QQ33231":   "arts.tsv",   # photographer
    # QQ42973 architect → engineering.tsv (assigned above)
    "QQ644687":  "arts.tsv",   # illustrator
    "QQ266569":  "arts.tsv",   # animator
    "QQ11569986":"arts.tsv",   # printmaker
    "QQ329439":  "arts.tsv",   # engraver  (fixed: not justice_of_the_peace)
    "QQ10862983":"arts.tsv",   # etcher
    "QQ1114448": "arts.tsv",   # cartoonist
    "QQ3658608": "arts.tsv",   # caricaturist
    "QQ715301":  "arts.tsv",   # comicsartist
    "QQ11892507":"arts.tsv",   # comicswriter
    "QQ191633":  "arts.tsv",   # mangaka
    "QQ17098559":"arts.tsv",   # penciller
    "QQ7541856": "arts.tsv",   # ceramicist
    "QQ3303330": "arts.tsv",   # calligrapher
    "QQ6138343": "arts.tsv",   # woodcarver
    "QQ2865798": "arts.tsv",   # glassartist
    "QQ3374326": "arts.tsv",   # muralist
    "QQ739437":  "arts.tsv",   # posterartist
    "QQ1925963": "arts.tsv",   # graphicartist
    "QQ627325":  "arts.tsv",   # graphicdesigner
    "QQ3391743": "arts.tsv",   # visualartist
    "QQ18074503":"arts.tsv",   # installationartist
    "QQ21550489":"arts.tsv",   # conceptualartist
    "QQ6934789": "arts.tsv",   # multimediaartist
    "QQ18216771":"arts.tsv",   # videoartist
    "QQ21477194":"arts.tsv",   # contemporaryartist
    "QQ21600439":"arts.tsv",   # landscapepainter
    "QQ16947657":"arts.tsv",   # lithographer
    "QQ13365770":"arts.tsv",   # copperengraver
    "QQ107212688":"arts.tsv",  # exlibrist
    "QQ15296811":"arts.tsv",   # draftsperson
    "QQ15977927":"arts.tsv",   # arteducator
    "QQ10732476":"arts.tsv",   # artcollector
    "QQ173950":  "arts.tsv",   # artdealer
    "QQ674426":  "arts.tsv",   # curator
    "QQ780596":  "arts.tsv",   # exhibitioncurator
    "QQ5697103": "arts.tsv",   # antiquarian
    "QQ998628":  "arts.tsv",   # illuminator
    "QQ3148760": "arts.tsv",   # botanicalillustrator
    "QQ5322166": "arts.tsv",   # designer
    "QQ3501317": "arts.tsv",   # fashiondesigner
    "QQ2133309": "arts.tsv",   # interiordesigner
    "QQ11455387":"arts.tsv",   # furnituredesigner
    "QQ10694573":"arts.tsv",   # textileartist
    "QQ437512":  "arts.tsv",   # weaver
    "QQ211423":  "arts.tsv",   # goldsmith
    "QQ2216340": "arts.tsv",   # silversmith
    "QQ336221":  "arts.tsv",   # jeweler
    "QQ2519376": "arts.tsv",   # jewellerydesigner
    "QQ1229025": "arts.tsv",   # typographer
    "QQ22343478":"arts.tsv",   # collagist
    "QQ329455":  "law.tsv",    # justiceof_the_peace
    "QQ487596":  "arts.tsv",   # dramaturge
    "QQ1776724": "arts.tsv",   # theatremanager
    "QQ1759246": "arts.tsv",   # theatricalproducer
    "QQ943995":  "arts.tsv",   # impresario
    # QQ2962070 productiondesigner → film.tsv (assigned above)
    # QQ15982858 motivationalspeaker → business.tsv (assigned below)

    # --- business.tsv ---
    "QQ43845":   "business.tsv",  # businessperson
    "QQ131524":  "business.tsv",  # entrepreneur
    "QQ806798":  "business.tsv",  # banker
    "QQ22687":   "business.tsv",  # bank (if P106 means banker type)
    "QQ215536":  "business.tsv",  # merchant
    "QQ1979607": "business.tsv",  # financier
    "QQ557880":  "business.tsv",  # investor
    "QQ2883465": "business.tsv",  # investmentbanker
    "QQ4182927": "business.tsv",  # stockbroker
    "QQ2961975": "business.tsv",  # businessexecutive
    "QQ6606110": "business.tsv",  # industrialist
    "QQ2516866": "business.tsv",  # publisher
    "QQ2462658": "business.tsv",  # manager
    "QQ1320883": "business.tsv",  # talentmanager
    "QQ1344174": "business.tsv",  # talentagent
    "QQ519076":  "business.tsv",  # real_estateagent
    "QQ3427922": "business.tsv",  # restaurateur
    "QQ3499072": "business.tsv",  # chef
    "QQ156839":  "business.tsv",  # cook
    "QQ998550":  "business.tsv",  # bookseller
    "QQ897317":  "business.tsv",  # winegrower
    "QQ1483709": "business.tsv",  # landowner
    "QQ12372582":"business.tsv",  # plantationowner
    "QQ17769800":"business.tsv",  # slavetrader
    "QQ500251":  "business.tsv",  # ship_owner
    "QQ1524582": "business.tsv",  # husbandryworker
    "QQ131512":  "business.tsv",  # farmer
    "QQ26481809":"business.tsv",  # sportsexecutive
    "QQ838476":  "business.tsv",  # sportingdirector
    "QQ15982858":"business.tsv",  # motivationalspeaker
    "QQ15978655":"business.tsv",  # consultant
    "QQ16532929":"business.tsv",  # administrator
    "QQ978044":  "business.tsv",  # executiveofficer
    "QQ2994387": "business.tsv",  # adviser
    "QQ326653":  "business.tsv",  # accountant
    "QQ12362622":"business.tsv",  # philanthropist
    "QQ15472169":"business.tsv",  # patronof_the_arts
    "QQ662729":  "business.tsv",  # publicfigure
    "QQ512314":  "business.tsv",  # socialite
    "QQ2906862": "business.tsv",  # influencer
    "QQ327029":  "business.tsv",  # mechanic

    # --- sports.tsv (general / multi-sport) ---
    "QQ2066131": "sports.tsv",  # athlete
    "QQ41583":   "sports.tsv",  # coach
    "QQ3246315": "sports.tsv",  # headcoach
    "QQ58825429":"sports.tsv",  # olympiccompetitor
    "QQ130495720":"sports.tsv", # paraathletics_competitor
    "QQ90496069":"sports.tsv",  # paraswimmer
    "QQ1708232": "sports.tsv",  # medalist
    "QQ15986539":"sports.tsv",  # sportsofficial
    "QQ202648":  "sports.tsv",  # referee
    "QQ50995749":"sports.tsv",  # sportsperson
    "QQ9149093": "sports.tsv",  # mountaineer
    "QQ3951423": "sports.tsv",  # rockclimber
    "QQ15306067":"sports.tsv",  # triathlete
    "QQ13561328":"sports.tsv",  # surfer
    "QQ17502714":"sports.tsv",  # skateboarder
    "QQ15709642":"sports.tsv",  # snowboarder
    "QQ13382460":"sports.tsv",  # marathonrunner
    "QQ4009406": "sports.tsv",  # sprinter
    "QQ11513337":"sports.tsv",  # athleticscompetitor
    "QQ13381753":"sports.tsv",  # middle_distancerunner
    "QQ4439155": "sports.tsv",  # long_distancerunner
    "QQ13724897":"sports.tsv",  # hurdler
    "QQ13382122":"sports.tsv",  # highjumper
    "QQ13381428":"sports.tsv",  # longjumper
    "QQ13464497":"sports.tsv",  # polevaulter
    "QQ13689":"sports.tsv",     # hammerthrower
    "QQ18534714":"sports.tsv",  # shotputter
    "QQ18510502":"sports.tsv",  # javelinthrower
    "QQ13381689":"sports.tsv",  # discusthrower
    "QQ17405793":"sports.tsv",  # racewalker
    "QQ13382355":"sports.tsv",  # archer
    "QQ13382519":"sports.tsv",  # tabletennis_player
    "QQ13141064":"sports.tsv",  # badmintonplayer
    "QQ16278103":"sports.tsv",  # squashplayer
    "QQ10833314":"sports.tsv",  # tennisplayer
    "QQ13219424":"sports.tsv",  # tenniscoach
    "QQ10843402":"sports.tsv",  # swimmer
    "QQ16004431":"sports.tsv",  # competitivediver
    "QQ18715859":"sports.tsv",  # synchronisedswimmer
    "QQ16004471":"sports.tsv",  # kayaker
    "QQ13382566":"sports.tsv",  # canoeist
    "QQ13383011":"sports.tsv",  # bobsledder
    "QQ13382981":"sports.tsv",  # luger
    "QQ13388586":"sports.tsv",  # skeletonracer
    "QQ4144610": "sports.tsv",  # alpineskier
    "QQ18617021":"sports.tsv",  # freestyleskier
    "QQ13382603":"sports.tsv",  # skijumper
    "QQ13382605":"sports.tsv",  # nordiccombined_skier
    "QQ19801627":"sports.tsv",  # skimountaineer
    "QQ16029547":"sports.tsv",  # biathlete
    "QQ10866633":"sports.tsv",  # speedskater
    "QQ18200514":"sports.tsv",  # shorttrack_speed_skater
    "QQ17361147":"sports.tsv",  # icedancer
    "QQ13219587":"sports.tsv",  # figureskater
    "QQ17516936":"sports.tsv",  # curler
    "QQ51751308":"sports.tsv",  # curlingcoach
    "QQ3014296": "sports.tsv",  # motorcycleracer
    "QQ378622":  "sports.tsv",  # racingdriver
    "QQ10349745":"sports.tsv",  # racingautomobile_driver
    "QQ10841764":"sports.tsv",  # formulaone_driver
    "QQ10842936":"sports.tsv",  # rallydriver
    "QQ63243629":"sports.tsv",  # speedwayrider
    "QQ2730732": "sports.tsv",  # equestrian
    "QQ13381458":"sports.tsv",  # dressagerider
    "QQ24797688":"sports.tsv",  # showjumper
    "QQ466640":  "sports.tsv",  # horsetrainer
    "QQ13218361":"sports.tsv",  # poloplayer
    "QQ846750":  "sports.tsv",  # jockey
    "QQ2309784": "sports.tsv",  # sportcyclist
    "QQ15117302":"sports.tsv",  # trackcyclist
    "QQ15117415":"sports.tsv",  # cyclo_crosscyclist
    "QQ3665646": "sports.tsv",  # basketballplayer
    "QQ5137571": "sports.tsv",  # basketballcoach
    "QQ12299841":"sports.tsv",  # cricketer
    "QQ2143894": "sports.tsv",  # cricketumpire
    "QQ10871364":"sports.tsv",  # baseballplayer
    "QQ11336312":"sports.tsv",  # professionalbaseball_player
    "QQ1186921": "sports.tsv",  # baseballmanager
    "QQ865935":  "sports.tsv",  # baseballcoach
    "QQ1856798": "sports.tsv",  # baseballumpire
    "QQ12840545":"sports.tsv",  # handballplayer
    "QQ13365201":"sports.tsv",  # handballcoach
    "QQ15117295":"sports.tsv",  # volleyballplayer
    "QQ17361156":"sports.tsv",  # beachvolleyball_player
    "QQ18515558":"sports.tsv",  # futsalplayer
    "QQ21057452":"sports.tsv",  # beachsoccer_player
    "QQ17682262":"sports.tsv",  # lacrosseplayer
    "QQ17619498":"sports.tsv",  # netballer
    "QQ13388442":"sports.tsv",  # skeletonracer (dup)
    "QQ18702210":"sports.tsv",  # bandyplayer
    "QQ29579227":"sports.tsv",  # bowlsplayer
    "QQ18574233":"sports.tsv",  # dartsplayer
    "QQ17165321":"sports.tsv",  # snookerplayer
    "QQ20540007":"sports.tsv",  # poolplayer
    "QQ15295720":"sports.tsv",  # pokerplayer
    "QQ18437198":"sports.tsv",  # bridgeplayer
    "QQ11303721":"sports.tsv",  # golfer
    "QQ476246":  "sports.tsv",  # sailor
    "QQ45199":   "sports.tsv",  # sailor (alt)
    "QQ1897112": "sports.tsv",  # skipper
    "QQ13382576":"sports.tsv",  # rower
    "QQ1690874": "sports.tsv",  # coxswain
    "QQ21121588":"sports.tsv",  # rowingcoach
    "QQ11338576":"sports.tsv",  # boxer
    "QQ11296761":"sports.tsv",  # kickboxer
    "QQ388513":  "sports.tsv",  # thaiboxer
    "QQ27889498":"sports.tsv",  # boxingmatch (if P106)
    "QQ6665249": "sports.tsv",  # judoka
    "QQ9017214": "sports.tsv",  # karateka
    "QQ13382533":"sports.tsv",  # taekwondoathlete
    "QQ11124885":"sports.tsv",  # martialartist
    "QQ12369333":"sports.tsv",  # amateurwrestler
    "QQ12839983":"sports.tsv",  # wrestler
    "QQ13474373":"sports.tsv",  # professionalwrestler
    "QQ13381572":"sports.tsv",  # artisticgymnast
    "QQ24037210":"sports.tsv",  # rhythmicgymnast
    "QQ16947675":"sports.tsv",  # gymnast
    "QQ13381376":"sports.tsv",  # weightlifter
    "QQ23845879":"sports.tsv",  # powerlifter
    "QQ15982795":"sports.tsv",  # bodybuilder
    "QQ10873124":"sports.tsv",  # chessplayer
    "QQ21141408":"sports.tsv",  # pentathlete
    "QQ15972912":"sports.tsv",  # modernpentathlete
    "QQ4379701": "sports.tsv",  # professionalgamer
    "QQ11538947":"sports.tsv",  # professionalshogi_player
    "QQ2727289": "sports.tsv",  # rikishi (sumo wrestler)
    "QQ26384038":"sports.tsv",  # eventrider
    "QQ18199024":"sports.tsv",  # hurler
    "QQ17351861":"sports.tsv",  # gaelicfootball_player
    "QQ4951095": "sports.tsv",  # bowler

    # --- genealogy.tsv (misc social) ---
    "QQ8963721": "genealogy.tsv",  # genealogist
    "QQ1475726": "genealogy.tsv",  # philatelist
    "QQ2004963": "genealogy.tsv",  # numismatist
    "QQ3243461": "genealogy.tsv",  # collector
    "QQ10429346":"genealogy.tsv",  # bibliographer
    "QQ864380":  "genealogy.tsv",  # biographer

    # --- misc.tsv (hard to categorize) ---
    "QQ3630699": "misc.tsv",   # gamedesigner
    "QQ54845077":"misc.tsv",   # role_playinggame_designer
    "QQ2629392": "misc.tsv",   # puppeteer
    "QQ337084":  "misc.tsv",   # dragqueen
    "QQ728711":  "misc.tsv",   # playboyplaymate
    "QQ3286043": "misc.tsv",   # eroticphotography_model
    "QQ4610556": "misc.tsv",   # model
    "QQ3357567": "misc.tsv",   # fashionmodel
    "QQ758780":  "misc.tsv",   # gardener
    "QQ154549":  "misc.tsv",   # carpenter
    "QQ820037":  "misc.tsv",   # miner
    "QQ808266":  "misc.tsv",   # bartender
    "QQ3400050": "misc.tsv",   # potter
    "QQ2000124": "misc.tsv",   # dearth_u00f3irstampa_u00ed_phoist
    "QQ3068305": "misc.tsv",   # salonni_u00e8re
    "QQ19698265":"misc.tsv",   # fashionphotographer
    "QQ15924544":"misc.tsv",   # lichenologist
    "QQ3190387": "misc.tsv",   # vigilante
    "QQ17307272":"misc.tsv",   # circusperformer
    "QQ15855449":"misc.tsv",   # magician
}

# Fix duplicate keys — Python dicts keep the last value for a key,
# but let's explicitly resolve conflicts by using a priority-ordered list
# and skipping already-assigned qids.

# Collect lines to move per destination
to_add = {}
moved_qids = set()

for qid, dest in mapping.items():
    if qid in moved_qids:
        continue  # first mapping wins
    if qid in entries:
        to_add.setdefault(dest, []).append(entries[qid])
        moved_qids.add(qid)

# Append to existing files / create new files
for dest, new_lines in to_add.items():
    dest_path = f"{BASE}/{dest}"
    if os.path.exists(dest_path):
        with open(dest_path, "a") as f:
            for line in new_lines:
                f.write(line + '\n')
        print(f"Appended {len(new_lines)} entries to {dest}")
    else:
        with open(dest_path, "w") as f:
            for line in new_lines:
                f.write(line + '\n')
        print(f"Created {dest} with {len(new_lines)} entries")

# Rewrite other.tsv with remaining entries
remaining = [line for line in lines if line.split('\t')[0] not in moved_qids]
with open(f"{BASE}/other.tsv", "w") as f:
    for line in remaining:
        f.write(line + '\n')

total_moved = len(moved_qids)
print(f"\nTotal moved: {total_moved} entries")
print(f"Remaining in other.tsv: {len(remaining)} entries")
