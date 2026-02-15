import os

BASE = "/Users/mjsuhonos/Documents/GitHub/wikicore/classes_smart"

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
    # --- aircraft.tsv ---
    "Q744913": "aircraft.tsv",   # aviation_incident
    "Q94993988": "aircraft.tsv", # commercial_traffic_aerodrome
    "Q62447": "aircraft.tsv",    # aerodrome

    # --- astronomy.tsv (rename star.tsv) ---
    "Q44559": "astronomy.tsv",   # extrasolar_planet
    "Q67206785": "astronomy.tsv",# near-ir_source
    "Q71798788": "astronomy.tsv",# uv-emission_source
    "Q67206691": "astronomy.tsv",# infrared_source
    "Q1348589": "astronomy.tsv", # lunar_crater
    "Q55818": "astronomy.tsv",   # impact_crater

    # --- building.tsv ---
    "Q3947": "building.tsv",     # house
    "Q23413": "building.tsv",    # castle
    "Q27686": "building.tsv",    # hotel
    "Q11303": "building.tsv",    # skyscraper
    "Q16560": "building.tsv",    # palace
    "Q1785071": "building.tsv",  # fort
    "Q751876": "building.tsv",   # château
    "Q879050": "building.tsv",   # manor_house
    "Q1802963": "building.tsv",  # mansion
    "Q1343246": "building.tsv",  # english_country_house
    "Q1307276": "building.tsv",  # single-family_detached_home
    "Q13402009": "building.tsv", # block_of_flats
    "Q1137809": "building.tsv",  # courthouse
    "Q39614": "building.tsv",    # cemetery
    "Q43501": "building.tsv",    # zoo
    "Q194195": "building.tsv",   # amusement_park
    "Q167346": "building.tsv",   # botanical_garden
    "Q7075": "building.tsv",     # library
    "Q33506": "building.tsv",    # museum
    "Q207694": "building.tsv",   # art_museum
    "Q1007870": "building.tsv",  # art_gallery
    "Q483110": "building.tsv",   # stadium
    "Q641226": "building.tsv",   # arena
    "Q24354": "building.tsv",    # theatre
    "Q11315": "building.tsv",    # shopping_centre
    "Q83405": "building.tsv",    # factory
    "Q16917": "building.tsv",    # hospital
    "Q39715": "building.tsv",    # lighthouse
    "Q40357": "building.tsv",    # prison
    "Q3917681": "building.tsv",  # embassy
    "Q811979": "building.tsv",   # built_structure
    "Q811430": "building.tsv",   # fixed_construction
    "Q17350442": "building.tsv", # venue
    "Q15911738": "building.tsv", # hydroelectric_power_station
    "Q543654": "building.tsv",   # rathaus
    "Q5003624": "building.tsv",  # memorial
    "Q4989906": "building.tsv",  # monument
    "Q179700": "building.tsv",   # statue
    "Q860861": "building.tsv",   # sculpture
    "Q166118": "building.tsv",   # archives
    "Q131596": "building.tsv",   # farm
    "Q820477": "building.tsv",   # mine
    "Q130003": "building.tsv",   # ski_resort
    "Q131734": "building.tsv",   # brewery

    # --- city.tsv ---
    "Q123705": "city.tsv",       # neighbourhood
    "Q1134686": "city.tsv",      # neighbourhood (alt class)
    "Q188509": "city.tsv",       # suburb
    "Q4845841": "city.tsv",      # settlement
    "Q3257686": "city.tsv",      # locality
    "Q148837": "city.tsv",       # polis

    # --- comic.tsv ---
    "Q21198342": "comic.tsv",    # manga_series
    "Q1004": "comic.tsv",        # comics

    # --- community.tsv ---
    "Q498162": "community.tsv",  # census-designated_place
    "Q1115575": "community.tsv", # civil_parish
    "Q17051044": "community.tsv",# mahalle
    "Q253019": "community.tsv",  # ortsteil
    "Q2514025": "community.tsv", # posyolok
    "Q1852859": "community.tsv", # cadastral_populated_place_in_the_netherlands
    "Q16127605": "community.tsv",# populated_place_in_syria
    "Q2023000": "community.tsv", # khutor
    "Q4224624": "community.tsv", # kmetstvo_of_bulgaria
    "Q56061": "community.tsv",   # administrative_territorial_entity
    "Q3677932": "community.tsv", # barrio_of_puerto_rico
    "Q55102916": "community.tsv",# parish_of_asturias
    "Q8776398": "community.tsv", # collective_population_entity_of_spain
    "Q98433835": "community.tsv",# suburb/locality_of_tasmania
    "Q20202352": "community.tsv",# locality_of_mexico
    "Q155239": "community.tsv",  # indian_reserve
    "Q3055118": "community.tsv", # single_entity_of_population

    # --- cultural.tsv ---
    "Q3305213": "cultural.tsv",  # painting
    "Q838948": "cultural.tsv",   # work_of_art
    "Q107357104": "cultural.tsv",# type_of_dance
    "Q132241": "cultural.tsv",   # festival
    "Q570116": "cultural.tsv",   # tourist_attraction
    "Q742421": "cultural.tsv",   # theatre_company
    "Q4504495": "cultural.tsv",  # award_ceremony
    "Q618779": "cultural.tsv",   # award

    # --- district.tsv ---
    "Q192287": "district.tsv",   # administrative_divisions_of_russia
    "Q18524218": "district.tsv", # canton_of_france
    "Q184188": "district.tsv",   # canton_of_france (alt)
    "Q2151232": "district.tsv",  # townland
    "Q15642541": "district.tsv", # human-geographic_territorial_entity
    "Q18691601": "district.tsv", # ward_of_tanzania
    "Q3812392": "district.tsv",  # union_council_of_bangladesh
    "Q2592651": "district.tsv",  # union_council_of_pakistan
    "Q104841013": "district.tsv",# hromada
    "Q777120": "district.tsv",   # borough_of_pennsylvania
    "Q192611": "district.tsv",   # riding
    "Q1639634": "district.tsv",  # local_government_area_of_nigeria
    "Q2755753": "district.tsv",  # area_of_london
    "Q1131296": "district.tsv",  # freguesia_of_portugal
    "Q1297": "district.tsv",     # just in case - won't match

    # --- geography.tsv (new) ---
    "Q736917": "geography.tsv",  # geological_formation
    "Q74817647": "geography.tsv",# aspect_in_a_geographic_region
    "Q473972": "geography.tsv",  # protected_area
    "Q39816": "geography.tsv",   # valley
    "Q618123": "geography.tsv",  # geographical_object
    "Q82794": "geography.tsv",   # region
    "Q271669": "geography.tsv",  # landform
    "Q179049": "geography.tsv",  # nature_reserve
    "Q35509": "geography.tsv",   # cave
    "Q4421": "geography.tsv",    # forest
    "Q8072": "geography.tsv",    # volcano
    "Q7944": "geography.tsv",    # earthquake
    "Q422211": "geography.tsv",  # site_of_special_scientific_interest
    "Q1620908": "geography.tsv", # historical_region

    # --- group.tsv ---
    "Q133311": "group.tsv",      # tribe

    # --- historic.tsv ---
    "Q839954": "historic.tsv",   # archaeological_site
    "Q17524420": "historic.tsv", # aspect_of_history
    "Q3024240": "historic.tsv",  # historical_country
    "Q13417114": "historic.tsv", # noble_family
    "Q465299": "historic.tsv",   # archaeological_culture
    "Q358": "historic.tsv",      # heritage_site
    "Q164950": "historic.tsv",   # dynasty
    "Q899409": "historic.tsv",   # gens
    "Q188913": "historic.tsv",   # plantation
    "Q113813711": "historic.tsv",# coin_type

    # --- language.tsv ---
    "Q33384": "language.tsv",    # dialect

    # --- literary.tsv ---
    "Q47461344": "literary.tsv", # written_work
    "Q571": "literary.tsv",      # book
    "Q277759": "literary.tsv",   # book_series
    "Q87167": "literary.tsv",    # manuscript
    "Q1667921": "literary.tsv",  # novel_series
    "Q1631107": "literary.tsv",  # bibliography
    "Q29154515": "literary.tsv", # chapter_of_the_bible

    # --- media.tsv (new) ---
    "Q14350": "media.tsv",       # radio_station
    "Q41298": "media.tsv",       # magazine
    "Q11032": "media.tsv",       # newspaper
    "Q5633421": "media.tsv",     # scientific_journal
    "Q1002697": "media.tsv",     # periodical
    "Q35127": "media.tsv",       # website
    "Q1555508": "media.tsv",     # radio_programme
    "Q737498": "media.tsv",      # academic_journal
    "Q2085381": "media.tsv",     # publishing_house
    "Q773668": "media.tsv",      # open-access_journal
    "Q1110794": "media.tsv",     # daily_newspaper
    "Q45400320": "media.tsv",    # open-access_publisher
    "Q561068": "media.tsv",      # specialty_channel
    "Q15265344": "media.tsv",    # broadcaster
    "Q73364223": "media.tsv",    # society_journal
    "Q24634210": "media.tsv",    # podcast

    # --- medical.tsv ---
    "Q12136": "medical.tsv",     # disease
    "Q929833": "medical.tsv",    # rare_disease
    "Q112965645": "medical.tsv", # symptom_or_sign
    "Q55788864": "medical.tsv",  # developmental_defect_during_embryogenesis

    # --- military.tsv ---
    "Q11446": "military.tsv",    # ship
    "Q178561": "military.tsv",   # battle
    "Q188055": "military.tsv",   # siege
    "Q198": "military.tsv",      # war
    "Q174736": "military.tsv",   # destroyer
    "Q428661": "military.tsv",   # u-boat
    "Q2811": "military.tsv",     # submarine
    "Q161705": "military.tsv",   # frigate
    "Q679165": "military.tsv",   # squadron
    "Q52371": "military.tsv",    # regiment
    "Q3199915": "military.tsv",  # massacre
    "Q124734": "military.tsv",   # rebellion
    "Q180684": "military.tsv",   # conflict
    "Q1261499": "military.tsv",  # naval_battle
    "Q124056273": "military.tsv",# artillery_model
    "Q100710213": "military.tsv",# combat_vehicle_model
    "Q18487055": "military.tsv", # missile_model
    "Q15142894": "military.tsv", # weapon_model
    "Q124078422": "military.tsv",# weapon_type
    "Q11167066": "military.tsv", # order_of_battle
    "Q2223653": "military.tsv",  # terrorist_attack
    "Q204577": "military.tsv",   # schooner
    "Q852190": "military.tsv",   # shipwreck
    "Q42314054": "military.tsv", # ammunition_model
    "Q575759": "military.tsv",   # war_memorial
    "Q12859788": "military.tsv", # steamship
    "Q132821": "military.tsv",   # murder
    "Q124757": "military.tsv",   # riot
    "Q1785071": "military.tsv",  # fort (also building - military wins for fort)

    # --- mountain.tsv ---
    "Q207326": "mountain.tsv",   # summit
    "Q54050": "mountain.tsv",    # hill
    "Q740445": "mountain.tsv",   # ridge
    "Q194408": "mountain.tsv",   # nunatak

    # --- music.tsv ---
    "Q482994": "music.tsv",      # album
    "Q134556": "music.tsv",      # single
    "Q169930": "music.tsv",      # extended_play
    "Q18127": "music.tsv",       # record_label
    "Q273057": "music.tsv",      # discography
    "Q1573906": "music.tsv",     # concert_tour
    "Q131186": "music.tsv",      # choir
    "Q10648343": "music.tsv",    # duo

    # --- olympic.tsv ---
    "Q46195901": "olympic.tsv",  # paralympics_delegation

    # --- organization.tsv ---
    "Q783794": "organization.tsv",  # company
    "Q6881511": "organization.tsv", # enterprise
    "Q4830453": "organization.tsv", # business
    "Q178790": "organization.tsv",  # trade_union
    "Q157031": "organization.tsv",  # foundation
    "Q955824": "organization.tsv",  # learned_society
    "Q732717": "organization.tsv",  # law_enforcement_agency
    "Q613142": "organization.tsv",  # law_firm
    "Q740752": "organization.tsv",  # transport_company
    "Q431289": "organization.tsv",  # brand
    "Q22687": "organization.tsv",   # bank
    "Q1589009": "organization.tsv", # privately_held_company
    "Q658255": "organization.tsv",  # subsidiary
    "Q786820": "organization.tsv",  # car_manufacturer
    "Q31855": "organization.tsv",   # research_institute
    "Q1664720": "organization.tsv", # institute
    "Q167270": "organization.tsv",  # trademark
    "Q18534542": "organization.tsv",# restaurant_chain

    # --- political.tsv ---
    "Q327333": "political.tsv",  # government_department
    "Q15238777": "political.tsv",# legislative_term
    "Q640506": "political.tsv",  # cabinet
    "Q192350": "political.tsv",  # ministry
    "Q131569": "political.tsv",  # treaty
    "Q15221623": "political.tsv",# bilateral_relation
    "Q19571328": "political.tsv",# electoral_result
    "Q355567": "political.tsv",  # royal_or_noble_rank
    "Q18759100": "political.tsv",# baronetcy
    "Q877358": "political.tsv",  # united_nations_security_council_resolution
    "Q49773": "political.tsv",   # social_movement
    "Q820655": "political.tsv",  # statute
    "Q2334719": "political.tsv", # legal_case
    "Q2135465": "political.tsv", # legal_term_or_legal_concept

    # --- railway.tsv ---
    "Q928830": "railway.tsv",    # metro_station
    "Q22808403": "railway.tsv",  # underground_station
    "Q22808404": "railway.tsv",  # station_located_on_surface
    "Q11670533": "railway.tsv",  # elevated_station
    "Q85882206": "railway.tsv",  # unmanned_station
    "Q121844689": "railway.tsv", # contracted_station
    "Q1147171": "railway.tsv",   # interchange_station
    "Q2175765": "railway.tsv",   # tram_stop
    "Q15079663": "railway.tsv",  # rapid_transit_line
    "Q332496": "railway.tsv",    # overtaking_station

    # --- recurring.tsv ---
    "Q1656682": "recurring.tsv", # event
    "Q1445650": "recurring.tsv", # holiday

    # --- religion.tsv (new) ---
    "Q16970": "religion.tsv",    # church
    "Q32815": "religion.tsv",    # mosque
    "Q842402": "religion.tsv",   # hindu_temple
    "Q34627": "religion.tsv",    # synagogue
    "Q5393308": "religion.tsv",  # buddhist_temple
    "Q44613": "religion.tsv",    # monastery
    "Q44539": "religion.tsv",    # temple
    "Q2977": "religion.tsv",     # cathedral
    "Q160742": "religion.tsv",   # abbey
    "Q108325": "religion.tsv",   # chapel
    "Q120560": "religion.tsv",   # minor_basilica
    "Q56242215": "religion.tsv", # catholic_cathedral
    "Q3146899": "religion.tsv",  # diocese_of_the_catholic_church
    "Q178885": "religion.tsv",   # deity

    # --- school.tsv ---
    "Q3918": "school.tsv",       # university
    "Q189004": "school.tsv",     # college
    "Q4671329": "school.tsv",    # academy
    "Q1663017": "school.tsv",    # engineering_college
    "Q902104": "school.tsv",     # private_university
    "Q2367225": "school.tsv",    # student_activity_unit

    # --- science.tsv (new) ---
    "Q16521": "science.tsv",     # taxon
    "Q23038290": "science.tsv",  # fossil_taxon
    "Q113145171": "science.tsv", # type_of_chemical_entity
    "Q7187": "science.tsv",      # gene
    "Q310890": "science.tsv",    # monotypic_taxon
    "Q65943": "science.tsv",     # theorem
    "Q12089225": "science.tsv",  # mineral_species
    "Q47487597": "science.tsv",  # monotypic_fossil_taxon
    "Q8054": "science.tsv",      # protein
    "Q417841": "science.tsv",    # protein_family
    "Q24034552": "science.tsv",  # mathematical_concept
    "Q11862829": "science.tsv",  # discipline
    "Q4886": "science.tsv",      # cultivar
    "Q8436": "science.tsv",      # family (taxonomy)
    "Q47154513": "science.tsv",  # structural_class_of_chemical_entities
    "Q976981": "science.tsv",    # formula
    "Q26401003": "science.tsv",  # individual_animal
    "Q726": "science.tsv",       # horse (animal)

    # --- sports.tsv ---
    "Q1079023": "sports.tsv",    # championship
    "Q1366722": "sports.tsv",    # final
    "Q3001412": "sports.tsv",    # horse_race
    "Q2990963": "sports.tsv",    # figure_skating_competition
    "Q2922711": "sports.tsv",    # bowl_game
    "Q27889498": "sports.tsv",   # boxing_match
    "Q2992826": "sports.tsv",    # athletic_conference
    "Q62391930": "sports.tsv",   # beauty_pageant_edition
    "Q58863414": "sports.tsv",   # female_beauty_pageant

    # --- technology.tsv (new) ---
    "Q7397": "technology.tsv",   # software
    "Q341": "technology.tsv",    # free_software
    "Q9135": "technology.tsv",   # operating_system
    "Q3231690": "technology.tsv",# car_model
    "Q23866334": "technology.tsv",# motorcycle_model
    "Q19723451": "technology.tsv",# smartphone_model
    "Q10929058": "technology.tsv",# product_model
    "Q20741022": "technology.tsv",# digital_camera_model
    "Q15057021": "technology.tsv",# engine_model
    "Q166142": "technology.tsv", # application
    "Q90834785": "technology.tsv",# racing_automobile_model
    "Q29654788": "technology.tsv",# unicode_character

    # --- television.tsv ---
    "Q3297186": "television.tsv",# limited_series
    "Q1259759": "television.tsv",# serial
    "Q526877": "television.tsv", # web_series

    # --- transport.tsv (new) ---
    "Q34442": "transport.tsv",   # road
    "Q79007": "transport.tsv",   # street
    "Q537127": "transport.tsv",  # road_bridge
    "Q12323": "transport.tsv",   # dam
    "Q12280": "transport.tsv",   # bridge
    "Q46622": "transport.tsv",   # motorway
    "Q12284": "transport.tsv",   # canal
    "Q83620": "transport.tsv",   # thoroughfare
    "Q1825472": "transport.tsv", # covered_bridge
    "Q44782": "transport.tsv",   # port

    # --- video.tsv ---
    "Q131436": "video.tsv",      # board_game
    "Q71631512": "video.tsv",    # tabletop_role-playing_game_supplement
    "Q1643932": "video.tsv",     # tabletop_role-playing_game
    "Q11410": "video.tsv",       # game

    # --- water.tsv ---
    "Q23442": "water.tsv",       # island
    "Q39594": "water.tsv",       # bay
    "Q35666": "water.tsv",       # glacier
    "Q34763": "water.tsv",       # peninsula
    "Q40080": "water.tsv",       # beach
    "Q191992": "water.tsv",      # headland
    "Q185113": "water.tsv",      # cape

    # --- wikimedia.tsv ---
    "Q18711811": "wikimedia.tsv",# map_data_module
    "Q3331189": "wikimedia.tsv", # version,_edition_or_translation
}

# Collect lines to move per destination
to_add = {}
moved_qids = set()

for qid, dest in mapping.items():
    if qid in entries:
        to_add.setdefault(dest, []).append(entries[qid])
        moved_qids.add(qid)

# Handle astronomy.tsv: rename star.tsv content + new entries
# First, read star.tsv if it exists
star_path = f"{BASE}/star.tsv"
if os.path.exists(star_path):
    with open(star_path) as f:
        star_lines = [l.rstrip('\n') for l in f if l.strip()]
    # Write astronomy.tsv with star.tsv content + new entries
    astro_new = to_add.get("astronomy.tsv", [])
    with open(f"{BASE}/astronomy.tsv", "w") as f:
        for line in star_lines:
            f.write(line + '\n')
        for line in astro_new:
            f.write(line + '\n')
    # Remove star.tsv
    os.remove(star_path)
    print(f"Renamed star.tsv -> astronomy.tsv, added {len(astro_new)} entries")
    del to_add["astronomy.tsv"]  # already handled

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
