import numpy as np
from datetime import date, timedelta, datetime
import matplotlib.pyplot as plt
import psycopg
from dataclasses import dataclass
from typing import Dict, List
import pandas as pd
import math



def get_visit_pairs_by_eta(df, delta_eta, eta_col='eta'):
    # Ordina per paziente e età
    df = df.sort_values(['id', eta_col])
    pairs = []

    for pid, group in df.groupby('id'):
        visits = group.sort_values(eta_col)
        n = len(visits)
        for i in range(n):
            for j in range(i + 1, n):
                eta_diff = visits.iloc[j][eta_col] - visits.iloc[i][eta_col]
                # Se la differenza di età è vicina a delta_eta (con tolleranza di ±0.1 anni)
                if abs(eta_diff - delta_eta) <= 0.1:
                    pair = {
                        'patient_id': pid,
                        'eta_t0': visits.iloc[i][eta_col],
                        'eta_t1': visits.iloc[j][eta_col],
                        'delta_eta': eta_diff,
                    }
                    # Calcola le differenze per tutte le altre colonne
                    for col in df.columns:
                        if col not in ['id', eta_col]:
                            pair[f'{col}_t0'] = visits.iloc[i][col]
                            pair[f'{col}_t1'] = visits.iloc[j][col]
                            pair[f'delta_{col}'] = visits.iloc[j][col] - visits.iloc[i][col]
                    pairs.append(pair)
                
    return pd.DataFrame(pairs)

def aggiungi_misure(list_pazienti,misurazioni, tipologia):
    for record in misurazioni:
            for paziente in list_pazienti:
                if record[0] == paziente.p_id:
                    paziente.add_misura(tipologia,                                            
                                        str(record[2]),         #data
                                        record[4],              #data_unix
                                        record[3])              #valore
                                        
    return list_pazienti

def aggiungi_osservazioni(list_pazienti,osservazioni, tipologia):
    for record in osservazioni:
            for paziente in list_pazienti:
                if record[0] == paziente.p_id:
                    val = record[3]
                    if tipologia =="Fisioterapia":
                        val = 1
                    if tipologia =="Diagnosi":
                        if val == "Scoliosi_Idiopatica":
                            val = 1
                        else:
                            val = 0

                    paziente.add_osservazione(tipologia,                                            
                                        str(record[2]),         #data
                                        record[4],              #data_unix
                                        val)                    #valore
    return list_pazienti

def bfill(lista):
    for j in range(len(lista[0])):  # per ogni colonna
        val = None
        for i in range(len(lista)-1, -1, -1):  # per ogni riga, dal basso verso l'alto
            if lista[i][j] is not None:
                val = lista[i][j]
            else:
                lista[i][j] = val
    return lista

def ffill(lista):
    for j in range(len(lista[0])):  # per ogni colonna
        val = None
        for i in range(len(lista)):  # per ogni riga
            if lista[i][j] is not None:
                val = lista[i][j]
            else:
                lista[i][j] = val
    return lista

def inclusion_criteria(df):
    rows = df[df["Riss sign"] >100].index
    df.drop(rows, inplace=True)
    df = df.sort_values(["id", "eta"])
    #df["delta_eta"] = df.groupby("id")["eta"].diff().fillna(0)
    return df

def create_lista_generica(list_pazienti, misure = [], osservazioni = []):
    completa = []

    for paziente in list_pazienti:
        visite = paziente.get_all_visite(misure, osservazioni)
        for visita in visite:

            completa.append(visita)
    df = pd.DataFrame(completa, columns=["id", "eta","gender", *misure, *osservazioni])

    
    if "Corsetto" in osservazioni:
        df = pd.get_dummies(df, columns=['Corsetto'], prefix='', prefix_sep='')
        df = df.rename(columns={
        '0': 'No_Brace',
        '45759350.0': 'Rigid_Brace',
        '45759350': 'Rigid_Brace',
        '2000000065.0': 'Very_Rigid_Brace',
        '2000000065': 'Very_Rigid_Brace',
        '45772663.0': 'Flexible_Brace',
        '45772663': 'Flexible_Brace'
    })
    df = df.astype(float)
    return df
                
            


########################################################################################################################################


#Classi
########################################################################################################################################

class Paziente:

    @dataclass
    class Visita:
        data: str
        data_unix: int
        eta: float
        misure: Dict[str,any]
        osservazioni: Dict[str,any] 
        def __str__(self):
            return f"""Visita:
Data: {self.data}
Eta: {self.eta}
Misurazioni: {self.misure}
Osservazioni: {self.osservazioni}"""
            
    def __init__(self, p_id, data_di_nascita, data_di_nascita_unix, gender, durata_osservazione_unix,misure=[], osservazioni=[]):
        self.p_id = p_id
        self.data_di_nascita = data_di_nascita
        self.data_di_nascita_unix = data_di_nascita_unix
        self.gender = gender
        self.durata_osservazione_unix = durata_osservazione_unix
        self.visite = []

    def add_visita(self, data, data_unix, misure = {}, osservazioni = {}):
        eta = self.calcolo_eta(data)
               
        self.visite.append(self.Visita(data,data_unix,eta, misure, osservazioni))
    
    def add_misura(self,tipologia, data, data_unix,valore):
        trovato = 0
        eta = self.calcolo_eta(data)
        for visite in self.visite:
            trovato = 0
            if visite.data_unix == data_unix or (eta >= visite.eta-0.1 and eta <= visite.eta+0.1) :
            #if visite.data_unix == data_unix:
                trovato = 1
                visite.misure[tipologia] = valore
                break
        if not trovato:
            self.add_visita(data,data_unix, {tipologia: valore}, {})
        self.visite.sort(key=lambda x: x.data_unix, reverse=False)


    def add_osservazione(self,tipologia, data, data_unix,valore):
        trovato = 0
        eta = self.calcolo_eta(data)
        for visite in self.visite:
            trovato = 0
            if visite.data_unix == data_unix or (eta >= visite.eta-0.1 and eta <= visite.eta+0.1):
            #if visite.data_unix == data_unix:
                trovato = 1
                visite.osservazioni[tipologia] = valore
                break
        if not trovato:
            self.add_visita(data,data_unix, {}, {tipologia: valore})
        self.visite.sort(key=lambda x: x.data_unix, reverse=False)


    def calcolo_eta(self, data):
        data = datetime.strptime(data, '%Y-%m-%d').date()
        eta = round((data - self.data_di_nascita) / timedelta(days=365.2425),2)
        
        return eta

    def get_all_visite(self, misure = [], osservazioni = []):
        visite = []
        for vis in self.visite:
            visita = []
            visita.append(self.p_id)
            visita.append(vis.eta)
            visita.append(self.gender)
            for tip in misure:
                visita.append(vis.misure.get(tip, None))
            for tip in osservazioni:
                if tip == "Corsetto" or tip == "Fisioterapia":
                    visita.append(vis.osservazioni.get(tip, 0))
                else:
                    visita.append(vis.osservazioni.get(tip, None))
            visite.append(visita)
            #visite = ffill([row.copy() for row in visite])  #Riempio con dati più vecchi, i nuovi None 
            #visite = bfill([row.copy() for row in visite])  #Se ci sono dei None all'inizio, li riempio coi successivi
            #visite = [row for row in visite if None not in row] #Se ci sono ancora dei None, in ogni caso quei dati sono inutilizzabili e li escludo

        return visite

        
            
            
            



    def __str__(self):
        
        return f"""
ID Paziente: {self.p_id},
Data di Nascita: {self.data_di_nascita}
Sesso: {self.gender}
Durata dell'osservazione: {self.durata_osservazione_unix}
"""

########################################################################################################################################

#Connessione al DB
########################################################################################################################################

def get_all_data(n_fetch):
    list_pazienti = []
    with psycopg.connect("""CHIEDERE A NEGRINI""") as conn:
        # Open a cursor to perform database operations
        with conn.cursor() as cur:
            cur.execute(""" SELECT p.person_id,
                        make_date(p.year_of_birth, p.month_of_birth, 1) AS data_di_nascita,
                        EXTRACT(epoch FROM make_date(p.year_of_birth, p.month_of_birth, 1)) AS data_di_nascita_unix,
                        p.gender_concept_id
                       FROM cdm.person p
                      ORDER BY p.person_id; """)
            #cobb =cur.fetchall()
            if n_fetch != 99999:
                cobb =cur.fetchmany(n_fetch)
            else:
                cobb = cur.fetchall()
            cur.execute("""SELECT person_id,
                        EXTRACT(epoch FROM observation_period_start_date),
                        EXTRACT(epoch FROM observation_period_end_date)
                        FROM cdm.observation_period
                        ORDER BY person_id""")
            #cobb_obs_per = cur.fetchall()
            cobb_obs_per =cur.fetchmany(n_fetch)
            for paz in cobb:
                p_id = paz[0]
                data_di_nascita = paz[1]
                data_di_nascita_unix = paz[2]
                gender = paz[3]
                for obs in cobb_obs_per:
                    if obs[0] == p_id:
                        durata_osservazione = obs[2] - obs[1]
                        break
                #Creo i pazienti
                list_pazienti.append(Paziente(p_id, data_di_nascita,  data_di_nascita_unix,0 if(gender==8507) else 1, durata_osservazione))
            
            cur.execute(""" SELECT m.person_id,
                        m.measurement_id,
                        m.measurement_date,
                        m.value_as_number,
                        EXTRACT(epoch FROM m.measurement_date) AS unix_timestamp
                       FROM cdm.measurement m
                      WHERE m.measurement_concept_id = 4111217 AND m.value_as_number IS NOT NULL
                      ORDER BY m.person_id, m.measurement_date;""")
            if n_fetch != 99999:
                cobb =cur.fetchmany(n_fetch)
            else:
                cobb = cur.fetchall()
            list_pazienti=aggiungi_misure(list_pazienti,cobb, "Cobb angle")
            
            cur.execute(""" SELECT m.person_id,
                        m.measurement_id,
                        m.measurement_date,
                        m.value_as_number,
                        EXTRACT(epoch FROM m.measurement_date) AS unix_timestamp
                       FROM cdm.measurement m
                      WHERE m.measurement_concept_id = 3661733
                      ORDER BY m.person_id, m.measurement_date;""")
            #cobb =cur.fetchall()
            if n_fetch != 99999:
                cobb =cur.fetchmany(n_fetch)
            else:
                cobb = cur.fetchall()
            list_pazienti=aggiungi_misure(list_pazienti,cobb, "Riss sign")

            cur.execute(""" SELECT m.person_id,
                        m.measurement_id,
                        m.measurement_date,
                        m.value_as_concept_id,
                        EXTRACT(epoch FROM m.measurement_date) AS unix_timestamp
                       FROM cdm.measurement m
                      WHERE m.measurement_concept_id = 4093194
                      ORDER BY m.person_id, m.measurement_date;""")
            #cobb =cur.fetchall()
            if n_fetch != 99999:
                cobb =cur.fetchmany(n_fetch)
            else:
                cobb = cur.fetchall()
            list_pazienti=aggiungi_misure(list_pazienti,cobb, "Curve Rigidity")

            cur.execute(""" SELECT m.person_id,
                        m.measurement_id,
                        m.measurement_date,
                        m.value_as_number,
                        EXTRACT(epoch FROM m.measurement_date) AS unix_timestamp
                       FROM cdm.measurement m
                      WHERE m.measurement_concept_id = 4093028
                      ORDER BY m.person_id, m.measurement_date;""")
            #cobb =cur.fetchall()
            if n_fetch != 99999:
                cobb =cur.fetchmany(n_fetch)
            else:
                cobb = cur.fetchall()
            list_pazienti=aggiungi_misure(list_pazienti,cobb, "Rib hump")

            cur.execute(""" SELECT m.person_id,
                        m.measurement_id,
                        m.measurement_date,
                        m.value_as_number,
                        EXTRACT(epoch FROM m.measurement_date) AS unix_timestamp
                       FROM cdm.measurement m
                      WHERE m.measurement_concept_id = 1621043
                      ORDER BY m.person_id, m.measurement_date;""")
            #cobb =cur.fetchall()
            if n_fetch != 99999:
                cobb =cur.fetchmany(n_fetch)
            else:
                cobb = cur.fetchall()
            list_pazienti=aggiungi_misure(list_pazienti,cobb, "Frontal imbalance")

            cur.execute(""" SELECT m.person_id,
                        m.measurement_id,
                        m.measurement_date,
                        m.value_as_number,
                        EXTRACT(epoch FROM m.measurement_date) AS unix_timestamp
                       FROM cdm.measurement m
                      WHERE m.measurement_concept_id = 2000000094
                      ORDER BY m.person_id, m.measurement_date;""")
            #cobb =cur.fetchall()
            if n_fetch != 99999:
                cobb =cur.fetchmany(n_fetch)
            else:
                cobb = cur.fetchall()
            list_pazienti=aggiungi_misure(list_pazienti,cobb, "Sagittal distance at C7 level")

            cur.execute(""" SELECT m.person_id,
                        m.measurement_id,
                        m.measurement_date,
                        m.value_as_number,
                        EXTRACT(epoch FROM m.measurement_date) AS unix_timestamp
                       FROM cdm.measurement m
                      WHERE m.measurement_concept_id = 2000000096
                      ORDER BY m.person_id, m.measurement_date;""")
            #cobb =cur.fetchall()
            if n_fetch != 99999:
                cobb =cur.fetchmany(n_fetch)
            else:
                cobb = cur.fetchall()
            list_pazienti=aggiungi_misure(list_pazienti,cobb, "Sagittal distance at T12 level")

            cur.execute(""" SELECT m.person_id,
                        m.measurement_id,
                        m.measurement_date,
                        m.value_as_number,
                        EXTRACT(epoch FROM m.measurement_date) AS unix_timestamp
                       FROM cdm.measurement m
                      WHERE m.measurement_concept_id = 2000000097
                      ORDER BY m.person_id, m.measurement_date;""")
            #cobb =cur.fetchall()
            if n_fetch != 99999:
                cobb =cur.fetchmany(n_fetch)
            else:
                cobb = cur.fetchall()
            list_pazienti=aggiungi_misure(list_pazienti,cobb, "Sagittal distance at L13 level")

            cur.execute(""" SELECT m.person_id,
                        m.measurement_id,
                        m.measurement_date,
                        m.value_as_number,
                        EXTRACT(epoch FROM m.measurement_date) AS unix_timestamp
                       FROM cdm.measurement m
                      WHERE m.measurement_concept_id = 2000000098
                      ORDER BY m.person_id, m.measurement_date;""")
            #cobb =cur.fetchall()
            if n_fetch != 99999:
                cobb =cur.fetchmany(n_fetch)
            else:
                cobb = cur.fetchall()
            list_pazienti=aggiungi_misure(list_pazienti,cobb, "Sagittal distance at S1 level")

            cur.execute(""" SELECT m.person_id,
                        m.measurement_id,
                        m.measurement_date,
                        m.value_as_number,
                        EXTRACT(epoch FROM m.measurement_date) AS unix_timestamp
                       FROM cdm.measurement m
                      WHERE m.measurement_concept_id = 4142943
                      ORDER BY m.person_id, m.measurement_date;""")
            #cobb =cur.fetchall()
            if n_fetch != 99999:
                cobb =cur.fetchmany(n_fetch)
            else:
                cobb = cur.fetchall()
            list_pazienti=aggiungi_misure(list_pazienti,cobb, "ATR")

            cur.execute(""" SELECT m.person_id,
                        m.measurement_id,
                        m.measurement_date,
                        m.value_as_number,
                        EXTRACT(epoch FROM m.measurement_date) AS unix_timestamp
                       FROM cdm.measurement m
                      WHERE m.measurement_concept_id = 2000000084
                      ORDER BY m.person_id, m.measurement_date;""")
            #cobb =cur.fetchall()
            if n_fetch != 99999:
                cobb =cur.fetchmany(n_fetch)
            else:
                cobb = cur.fetchall()
            list_pazienti=aggiungi_misure(list_pazienti,cobb, "Trace")
    
    
            cur.execute(""" SELECT o.person_id,
                        o.observation_id,
                        o.observation_date,
                        o.value_as_number,
                        EXTRACT(epoch FROM o.observation_date) AS unix_timestamp
                        FROM cdm.observation o
                        WHERE o.observation_concept_id = 36716213 and o.observation_source_value = 'scoliosivisits_kt_effettuata'
                        ORDER BY o.person_id, o.observation_date;""")
            #cobb =cur.fetchall()
            if n_fetch != 99999:
                cobb =cur.fetchmany(n_fetch)
            else:
                cobb = cur.fetchall()
            list_pazienti=aggiungi_osservazioni(list_pazienti,cobb, "Fisioterapia")
            
            cur.execute(""" SELECT o.person_id,
                        o.observation_id,
                        o.observation_date,
                        o.value_as_concept_id,
                        EXTRACT(epoch FROM o.observation_date) AS unix_timestamp
                        FROM cdm.observation o
                        WHERE o.observation_concept_id = 4210331 and o.observation_source_value = 'scoliosivisits_tipo_corsetto'
                        ORDER BY o.person_id, o.observation_date;""")
    
            #cobb =cur.fetchall()
            if n_fetch != 99999:
                cobb =cur.fetchmany(n_fetch)
            else:
                cobb = cur.fetchall()

            
            list_pazienti=aggiungi_osservazioni(list_pazienti,cobb, "Corsetto")
    
            cur.execute(""" SELECT o.person_id,
                        o.observation_id,
                        o.observation_date,
                        o.value_as_number,
                        EXTRACT(epoch FROM o.observation_date) AS unix_timestamp
                        FROM cdm.observation o
                        WHERE o.observation_concept_id = 4210331 and o.observation_source_value = 'scoliosivisits_ore_gg_corsetto'
                        ORDER BY o.person_id, o.observation_date;""")
    
            if n_fetch != 99999:
                cobb =cur.fetchmany(n_fetch)
            else:
                cobb = cur.fetchall()
            list_pazienti=aggiungi_osservazioni(list_pazienti,cobb, "Corsetto:ore_gg")

            cur.execute(""" SELECT o.person_id,
                        o.observation_id,
                        o.observation_date,
                        o.value_as_number,
                        EXTRACT(epoch FROM o.observation_date) AS unix_timestamp
                        FROM cdm.observation o
                        WHERE o.observation_concept_id = 2000000321
                        ORDER BY o.person_id, o.observation_date;""")
            #cobb =cur.fetchall()
            if n_fetch != 99999:
                cobb =cur.fetchmany(n_fetch)
            else:
                cobb = cur.fetchall()
            list_pazienti=aggiungi_osservazioni(list_pazienti,cobb, "SRS-7")

            cur.execute(""" SELECT o.person_id,
                        o.observation_id,
                        o.observation_date,
                        o.value_as_number,
                        EXTRACT(epoch FROM o.observation_date) AS unix_timestamp 
                        FROM cdm.observation o
                        WHERE o.observation_concept_id = 4112438 and o.observation_source_value = 'questionnairesrsanswers_risultato_totale_media'
                        ORDER BY o.person_id, o.observation_date;""") 
            #cobb =cur.fetchall()
            if n_fetch != 99999:
                cobb =cur.fetchmany(n_fetch)
            else:
                cobb = cur.fetchall()
            list_pazienti=aggiungi_osservazioni(list_pazienti,cobb, "Average SRS")

            cur.execute(""" SELECT o.person_id,
                        o.observation_id,
                        o.observation_date,
                        o.value_as_number,
                        EXTRACT(epoch FROM o.observation_date) AS unix_timestamp
                        FROM cdm.observation o
                        WHERE o.observation_concept_id = 4086154 and o.observation_source_value = 'questionnairesrsanswers_risultato_funz_media'
                        ORDER BY o.person_id, o.observation_date;""")
            #cobb =cur.fetchall()
            if n_fetch != 99999:
                cobb =cur.fetchmany(n_fetch)
            else:
                cobb = cur.fetchall()
            list_pazienti=aggiungi_osservazioni(list_pazienti,cobb, "SRS: Function average")

            cur.execute(""" SELECT o.person_id,
                        o.observation_id,
                        o.observation_date,
                        o.value_as_number,
                        EXTRACT(epoch FROM o.observation_date) AS unix_timestamp
                        FROM cdm.observation o
                        WHERE o.observation_concept_id = 44803355 and o.observation_source_value = 'questionnairesrsanswers_risultato_psiche_media'
                        ORDER BY o.person_id, o.observation_date;""")
            #cobb =cur.fetchall()
            if n_fetch != 99999:
                cobb =cur.fetchmany(n_fetch)
            else:
                cobb = cur.fetchall()
            list_pazienti=aggiungi_osservazioni(list_pazienti,cobb, "SRS: Mental Health average")

            cur.execute(""" SELECT o.person_id,
                        o.observation_id,
                        o.observation_date,
                        o.value_as_number,
                        EXTRACT(epoch FROM o.observation_date) AS unix_timestamp
                        FROM cdm.observation o
                        WHERE o.observation_concept_id = 4329041 and o.observation_source_value = 'questionnairesrsanswers_risultato_dolore_media'
                        ORDER BY o.person_id, o.observation_date;""")
            #cobb =cur.fetchall()
            if n_fetch != 99999:
                cobb =cur.fetchmany(n_fetch)
            else:
                cobb = cur.fetchall()
            list_pazienti=aggiungi_osservazioni(list_pazienti,cobb, "SRS: Pain average")

            cur.execute(""" SELECT o.person_id,
                        o.observation_id,
                        o.observation_date,
                        o.value_as_number,
                        EXTRACT(epoch FROM o.observation_date) AS unix_timestamp
                        FROM cdm.observation o
                        WHERE o.observation_concept_id = 46272230 and o.observation_source_value = 'questionnairesrsanswers_risultato_estetica_media'
                        ORDER BY o.person_id, o.observation_date;""")
            #cobb =cur.fetchall()
            if n_fetch != 99999:
                cobb =cur.fetchmany(n_fetch)
            else:
                cobb = cur.fetchall()
            list_pazienti=aggiungi_osservazioni(list_pazienti,cobb, "SRS: Assessment of self-image average")

            cur.execute(""" SELECT o.person_id,
                        o.observation_id,
                        o.observation_date,
                        o.value_as_number,
                        EXTRACT(epoch FROM o.observation_date) AS unix_timestamp
                        FROM cdm.observation o
                        WHERE o.observation_concept_id = 35622067 and o.observation_source_value = 'questionnairesrsanswers_risultato_soddisfazione_media'
                        ORDER BY o.person_id, o.observation_date;""")
            #cobb =cur.fetchall()
            if n_fetch != 99999:
                cobb =cur.fetchmany(n_fetch)
            else:
                cobb = cur.fetchall()
            list_pazienti=aggiungi_osservazioni(list_pazienti,cobb, "SRS: Patient satisfaction score average")

            cur.execute(""" SELECT o.person_id,
                        o.observation_id,
                        o.observation_date,
                        o.value_source_value,
                        EXTRACT(epoch FROM o.observation_date) AS unix_timestamp
                        FROM cdm.observation o
                        WHERE o.observation_concept_id = 40766659 
                        ORDER BY o.person_id, o.observation_date;""")
            #cobb =cur.fetchall()
            if n_fetch != 99999:
                cobb =cur.fetchmany(n_fetch)
            else:
                cobb = cur.fetchall()
            list_pazienti=aggiungi_osservazioni(list_pazienti,cobb, "End of treatment")

            cur.execute(""" SELECT 
                        c.person_id,
                        c.condition_occurrence_id,
                        c.condition_start_date,
                        c.condition_source_value,
                        EXTRACT(epoch FROM c.condition_start_date) AS unix_timestamp
                        FROM cdm.condition_occurrence c
                        where c.condition_status_concept_id = 4307107
                        ORDER BY condition_occurrence_id, c.condition_start_date;""")
            #cobb =cur.fetchall()
            if n_fetch != 99999:
                cobb =cur.fetchmany(n_fetch)
            else:
                cobb = cur.fetchall()
            list_pazienti=aggiungi_osservazioni(list_pazienti,cobb, "Diagnosi")
    return list_pazienti
########################################################################################################################################