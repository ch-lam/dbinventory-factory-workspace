/*
** Create MONITORING role for the dbInventory collector, to be deployed on all
** PostgreSQL instances (it should be part of a post-deployment template for
** a new cluster ; this script is for manual deployment and documentation
** purposes only — use secret server to retrieve the correct password).
*/

-- Role en lecture seule, base sur le role integre pg_monitor (PG10+) qui donne
-- acces aux vues pg_stat_*/pg_settings sans droits d'ecriture.
-- et grant access to pg_hba_file_rules() to read the pg_hba.conf file (PG15+)
CREATE ROLE monitoring WITH LOGIN PASSWORD '*******************************' CONNECTION LIMIT 5;
GRANT pg_monitor TO monitoring;
GRANT SELECT ON pg_hba_file_rules TO monitoring;
GRANT EXECUTE ON FUNCTION pg_hba_file_rules() to monitoring;

-- pg_monitor ne donne pas CONNECT sur les bases applicatives : a executer
-- pour chaque base a inventorier (taille, extensions, ACL).
-- GRANT CONNECT ON DATABASE <dbname> TO monitoring;

-- Notes :
--  - pg_hba_file_rules : lecture complete du fichier pg_hba.conf disponible a
--    tout role depuis PG15. Avant PG15, seul un superuser voit toutes les
--    lignes (les colonnes sensibles sont sinon masquees) -> a verifier selon
--    la version des instances ciblees.
--  - aclexplode()/pg_database.datacl (droits PUBLIC) ne necessitent pas de
--    privilege particulier au-dela de CONNECT.

-- Pour changer le mot de passe ulterieurement :
-- ALTER ROLE monitoring WITH PASSWORD '*******************************';

-- Ajouter ces lignes au fichier /opt/postgres/work/data/pg_hba.conf
-- (verifier path: show hba_file; )
vi /opt/postgres/work/data/pg_hba.conf

# access for dbInventory/monitoring
host    all             monitoring      192.168.3.115/32        md5

psql>
-- sous psql recharger la configuration
SELECT * FROM pg_hba_file_rules WHERE error IS NOT NULL;

-- if OK, then reload the configuration to apply the new rules
SELECT pg_reload_conf();
