prompt *************************************************************
prompt ******************** DROP TABLE *****************************
prompt *************************************************************


DROP TABLE PATIENTS CASCADE CONSTRAINTS;
DROP TABLE MEDECINS CASCADE CONSTRAINTS;
DROP TABLE CONSULTATIONS CASCADE CONSTRAINTS;
DROP TABLE DERNIERECONSULTATION CASCADE CONSTRAINTS;
DROP TABLE SPECIALITES CASCADE CONSTRAINTS;
DROP SEQUENCE patient_seq;
DROP SEQUENCE medecin_seq;

prompt *************************************************************
prompt ******************** CREATE TABLE ***************************
prompt *************************************************************

CREATE TABLE PATIENTS (
  IdPatient NUMBER PRIMARY KEY,
  NomPatient VARCHAR2(50) NOT NULL,
  PrenomPatient VARCHAR2(50) NOT NULL,
  AdressePatient VARCHAR2(100),
  CONSTRAINT chk_patients_nom_prenom CHECK (
    LENGTH(TRIM(NomPatient)) >= 2 AND LENGTH(TRIM(PrenomPatient)) >= 2
  ),
  CONSTRAINT chk_patients_adresse CHECK (
    LENGTH(TRIM(AdressePatient)) >= 10
  )
);

CREATE TABLE MEDECINS (
  IdMedecin NUMBER PRIMARY KEY,
  NomMedecin VARCHAR2(50) NOT NULL,
  PrenomMedecin VARCHAR2(50) NOT NULL,
  CONSTRAINT chk_medecins_nom_prenom CHECK (
    LENGTH(TRIM(NomMedecin)) >= 2 AND LENGTH(TRIM(PrenomMedecin)) >= 2
  )
);

CREATE TABLE SPECIALITES (
  IdCabinet NUMBER,
  IdMedecin NUMBER,
  SpecialiteMedecin VARCHAR2(50) NOT NULL,
  PRIMARY KEY (IdCabinet, IdMedecin),
  FOREIGN KEY (IdMedecin) REFERENCES MEDECINS(IdMedecin)
);

CREATE TABLE CONSULTATIONS (
  IdPatient NUMBER,
  DerniereConsultation DATE,
  IdCabinet NUMBER,
  IdMedecin NUMBER,
  PRIMARY KEY (IdPatient, DerniereConsultation),
  FOREIGN KEY (IdPatient) REFERENCES PATIENTS(IdPatient),
  FOREIGN KEY (IdCabinet, IdMedecin) REFERENCES SPECIALITES(IdCabinet, IdMedecin)
);

CREATE TABLE DERNIERECONSULTATION (
  IdPatient NUMBER,
  IdCabinet NUMBER,
  DerniereConsultation DATE,
  PRIMARY KEY (IdPatient, IdCabinet),
  FOREIGN KEY (IdPatient) REFERENCES PATIENTS(IdPatient)
);

--Création d'indexe: 
CREATE INDEX idx_nom_patient ON PATIENTS(NomPatient);
CREATE INDEX idx_specialte ON SPECIALITES (SpecialiteMedecin);

CREATE SEQUENCE patient_seq START WITH 1 INCREMENT BY 1;
CREATE SEQUENCE medecin_seq START WITH 1 INCREMENT BY 1;

/*un trigger pour vérifier si la date de la consultation est dans le passé lors de
l'insertion dans la table CONSULTATIONS*/
CREATE OR REPLACE TRIGGER trg_cons_bef_insert
BEFORE INSERT ON CONSULTATIONS
FOR EACH ROW
DECLARE
  date_in_future EXCEPTION;
BEGIN
  IF :NEW.DerniereConsultation > SYSDATE THEN
    RAISE date_in_future;
  END IF;
EXCEPTION
  WHEN date_in_future THEN
    RAISE_APPLICATION_ERROR(-20001, 'La date de la consultation doit être dans le passé.');
END;
/


/*
Déclencheur pour mettre à jour la table DERNIERECONSULTATION chaque fois qu'une nouvelle
consultation est insérée dans la table CONSULTATIONS
*/
CREATE OR REPLACE TRIGGER update_derniere_consultation
AFTER INSERT ON CONSULTATIONS
FOR EACH ROW
BEGIN
  UPDATE DERNIERECONSULTATION
  SET DerniereConsultation = :NEW.DerniereConsultation
  WHERE IdPatient = :NEW.IdPatient
    AND IdCabinet = :NEW.IdCabinet;

  IF SQL%ROWCOUNT = 0 THEN
    INSERT INTO DERNIERECONSULTATION (IdPatient, IdCabinet, DerniereConsultation)
    VALUES (:NEW.IdPatient, :NEW.IdCabinet, :NEW.DerniereConsultation);
  END IF;
END;
/


/*
Ce déclencheur s'assure que le médecin assigné à une consultation est bien 
enregistré avec une spécialité dans la table SPECIALITES
*/
CREATE OR REPLACE TRIGGER trg_check_medecin_specialite
BEFORE INSERT ON CONSULTATIONS
FOR EACH ROW
DECLARE
  cnt NUMBER;
BEGIN
  -- Vérifie si le couple IdMedecin et IdCabinet existe dans la table SPECIALITES,
  -- ce qui signifie que le médecin a la bonne spécialité pour cette consultation
  SELECT COUNT(*)
  INTO cnt
  FROM SPECIALITES
  WHERE IdMedecin = :NEW.IdMedecin AND IdCabinet = :NEW.IdCabinet;
  

  -- Si le couple n'existe pas dans la table SPECIALITES, déclenche une erreur,
  -- indiquant que le médecin n'a pas la bonne spécialité pour cette consultation
  IF cnt = 0 THEN
    RAISE_APPLICATION_ERROR(-20002, 'Le médecin assigné à la consultation n''a pas la bonne spécialité. Le couple IdMedecin et IdCabinet n''existe pas dans la table SPECIALITES.');
  END IF;
END;
/

/*
Procédure qui permet d'ajouter un nouveau médecin en spécifiant les cabinets rattachés et la spécialité. La procédure prend en paramètres le nom, le prénom du médecin,
l'identifiant du cabinet et la spécialité du médecin.

*/
CREATE OR REPLACE PROCEDURE add_new_medecin (
  p_NomMedecin IN MEDECINS.NomMedecin%TYPE,
  p_PrenomMedecin IN MEDECINS.PrenomMedecin%TYPE,
  p_IdCabinet IN SPECIALITES.IdCabinet%TYPE,
  p_SpecialiteMedecin IN SPECIALITES.SpecialiteMedecin%TYPE
) AS
  v_IdMedecin MEDECINS.IdMedecin%TYPE;
BEGIN
  -- Insérer le nouveau médecin dans la table MEDECINS
  INSERT INTO MEDECINS (IdMedecin, NomMedecin, PrenomMedecin)
  VALUES (medecin_seq.NEXTVAL,p_NomMedecin, p_PrenomMedecin)
  RETURNING IdMedecin INTO v_IdMedecin;

  -- Insérer la spécialité et le cabinet rattaché du médecin dans la table SPECIALITES
  INSERT INTO SPECIALITES (IdCabinet, IdMedecin, SpecialiteMedecin)
  VALUES (p_IdCabinet, v_IdMedecin, p_SpecialiteMedecin);

  COMMIT;
EXCEPTION
  WHEN OTHERS THEN
    ROLLBACK;
    RAISE;
END;
/

/*

procédure qui permet de transférer un médecin d'un cabinet à un autre
et de mettre à jour sa spécialité
*/
CREATE OR REPLACE PROCEDURE transfer_medecin_to_cabinet (
  p_IdMedecin IN MEDECINS.IdMedecin%TYPE,
  p_OldCabinet IN SPECIALITES.IdCabinet%TYPE,
  p_NewCabinet IN SPECIALITES.IdCabinet%TYPE,
  p_NewSpecialite IN SPECIALITES.SpecialiteMedecin%TYPE
) AS
BEGIN
  -- Supprimer la spécialité du médecin dans l'ancien cabinet
  DELETE FROM SPECIALITES
  WHERE IdCabinet = p_OldCabinet
    AND IdMedecin = p_IdMedecin;

  -- Ajouter la nouvelle spécialité du médecin dans le nouveau cabinet
  INSERT INTO SPECIALITES (IdCabinet, IdMedecin, SpecialiteMedecin)
  VALUES (p_NewCabinet, p_IdMedecin, p_NewSpecialite);

  COMMIT;
EXCEPTION
  WHEN OTHERS THEN
    ROLLBACK;
    RAISE;
END;
/

/* Création d'une vue pour obtenir les détails d'une consultation, 
y compris les informations sur le patient, le médecin et la spécialité */
CREATE OR REPLACE VIEW consultation_details AS
SELECT
  c.IdPatient,
  p.NomPatient,
  p.PrenomPatient,
  p.AdressePatient,
  c.DerniereConsultation,
  c.IdCabinet,
  c.IdMedecin,
  m.NomMedecin,
  m.PrenomMedecin,
  s.SpecialiteMedecin
FROM
  CONSULTATIONS c
  JOIN PATIENTS p ON c.IdPatient = p.IdPatient
  JOIN SPECIALITES s ON (c.IdCabinet = s.IdCabinet AND c.IdMedecin = s.IdMedecin)
  JOIN MEDECINS m ON s.IdMedecin = m.IdMedecin;

/*exemple interrogation vue 
SELECT *
FROM consultation_details
WHERE IdPatient = 1
  AND DerniereConsultation = TO_DATE('2023-03-01', 'YYYY-MM-DD');
*/

/*
Vue qui retourne le nombre de consultations effectuées par mois
*/
CREATE OR REPLACE VIEW consultations_par_mois AS
SELECT
  TRUNC(c.DerniereConsultation, 'MM') AS mois,
  COUNT(*) AS nb_consultations
FROM
  CONSULTATIONS c
GROUP BY
  TRUNC(c.DerniereConsultation, 'MM')
ORDER BY
  mois;

/*exemple appel à la vue
SELECT *
FROM consultations_par_mois;
*/

-- Insertions dans la table PATIENTS
INSERT INTO PATIENTS (IdPatient, NomPatient, PrenomPatient, AdressePatient)
VALUES (patient_seq.NEXTVAL, 'Martin', 'Jean', '25 Rue des Lilas, 75001 Paris');

INSERT INTO PATIENTS (IdPatient, NomPatient, PrenomPatient, AdressePatient)
VALUES (patient_seq.NEXTVAL, 'Dubois', 'Marie', '10 Avenue du Château, 69001 Lyon');

-- Insertions dans la table MEDECINS
INSERT INTO MEDECINS (IdMedecin, NomMedecin, PrenomMedecin)
VALUES (medecin_seq.NEXTVAL, 'Leroy', 'Sophie');

INSERT INTO MEDECINS (IdMedecin, NomMedecin, PrenomMedecin)
VALUES (medecin_seq.NEXTVAL, 'Moreau', 'Pierre');

-- Insertions dans la table SPECIALITES
INSERT INTO SPECIALITES (IdCabinet, IdMedecin, SpecialiteMedecin)
VALUES (1, 1, 'Cardiologue');

INSERT INTO SPECIALITES (IdCabinet, IdMedecin, SpecialiteMedecin)
VALUES (2, 2, 'Dentiste');

-- Insertions dans la table CONSULTATIONS
INSERT INTO CONSULTATIONS (IdPatient, DerniereConsultation, IdCabinet, IdMedecin)
VALUES (1, TO_DATE('2023-02-15', 'YYYY-MM-DD'), 1, 1);

INSERT INTO CONSULTATIONS (IdPatient, DerniereConsultation, IdCabinet, IdMedecin)
VALUES (2, TO_DATE('2023-01-30', 'YYYY-MM-DD'), 2, 2);

-- Insertions supplémentaires dans la table PATIENTS
INSERT INTO PATIENTS (IdPatient, NomPatient, PrenomPatient, AdressePatient)
VALUES (patient_seq.NEXTVAL, 'Bernard', 'Claire', '15 Rue de la Paix, 13001 Marseille');

INSERT INTO PATIENTS (IdPatient, NomPatient, PrenomPatient, AdressePatient)
VALUES (patient_seq.NEXTVAL, 'Girard', 'Nicolas', '20 Avenue de la République, 33000 Bordeaux');

-- Insertions supplémentaires dans la table MEDECINS
INSERT INTO MEDECINS (IdMedecin, NomMedecin, PrenomMedecin)
VALUES (medecin_seq.NEXTVAL, 'Lemaire', 'Caroline');

INSERT INTO MEDECINS (IdMedecin, NomMedecin, PrenomMedecin)
VALUES (medecin_seq.NEXTVAL, 'Roux', 'Bruno');

-- Insertions supplémentaires dans la table SPECIALITES
INSERT INTO SPECIALITES (IdCabinet, IdMedecin, SpecialiteMedecin)
VALUES (3, 3, 'Dermatologue');

INSERT INTO SPECIALITES (IdCabinet, IdMedecin, SpecialiteMedecin)
VALUES (4, 4, 'Orthopédiste');

-- Insertions supplémentaires dans la table CONSULTATIONS
INSERT INTO CONSULTATIONS (IdPatient, DerniereConsultation, IdCabinet, IdMedecin)
VALUES (3, TO_DATE('2023-03-01', 'YYYY-MM-DD'), 3, 3);

INSERT INTO CONSULTATIONS (IdPatient, DerniereConsultation, IdCabinet, IdMedecin)
VALUES (4, TO_DATE('2023-03-10', 'YYYY-MM-DD'), 4, 4);

INSERT INTO CONSULTATIONS (IdPatient, DerniereConsultation, IdCabinet, IdMedecin)
VALUES (1, TO_DATE('2023-01-25', 'YYYY-MM-DD'), 4, 4);

--Créer un rôle pour les medecins
DROP ROLE medecin_role;
CREATE ROLE medecin_role;

--Créer un rôle pour les secrétaires
DROP ROLE secretaire_role;
CREATE ROLE secretaire_role;

--Accorder les droits aux rôle de medecin
GRANT SELECT,UPDATE ON MEDECINS TO medecin_role;
GRANT SELECT,UPDATE ON SPECIALITES TO medecin_role;
GRANT SELECT ON PATIENTS TO medecin_role;
GRANT SELECT,UPDATE ON MEDECINS TO medecin_role;
GRANT SELECT,INSERT, UPDATE ON CONSULTATIONS TO medecin_role;

--Accorder les droit au rôle de secretaire

GRANT SELECT,INSERT, UPDATE ON PATIENTS TO secretaire_role;
GRANT SELECT, INSERT, UPDATE ON MEDECINS TO secretaire_role;
GRANT SELECT, INSERT, UPDATE ON SPECIALITES TO secretaire_role;
GRANT SELECT, INSERT, UPDATE ON CONSULTATIONS TO secretaire_role;


GRANT medecin_role TO L3_54;
GRANT secretaire_role TO L3_57;

select * from consultation_details;



