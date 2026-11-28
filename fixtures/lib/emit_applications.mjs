// Écriture du registre applicatif du jeu de démonstration.
//
// Rien ici ne passe par un CSV, et c'est la différence de nature : les 56 autres
// fichiers sont ce qu'une collecte a VU, celui-ci est ce qu'un humain a SAISI.
// Il n'y a donc ni table de staging ni ETL à traverser — la sortie est un script
// qui appelle pkg_dbinv_application, comme le ferait l'écran.
//
// Passer par l'API plutôt que par des INSERT est délibéré : c'est ce qui exerce
// les refus (un groupe injoignable, un document sans contenu ni lien), les
// triggers de journal, et la cascade de rattachement. Un jeu chargé par INSERT
// aurait la même allure à l'écran et n'aurait rien prouvé.
//
// La résolution des entités se fait par clé naturelle et par `select into`,
// comme dans emit_discovery : si le parc n'a pas produit l'entité attendue,
// no_data_found arrête la chaîne au lieu de livrer un registre amputé dont
// l'écran ne dirait rien.

import { writeFileSync } from 'node:fs';
import { join } from 'node:path';

const q = (s) => s === null || s === undefined ? 'null' : `'${String(s).replace(/'/g, "''")}'`;
const n = (v) => v === null || v === undefined ? 'null' : String(v);
const d = (s) => s === null || s === undefined ? 'null' : `date '${s}'`;

// ---------------------------------------------------------------------------
// Ce que chaque application couvre.
//
// Le jeton `app` est celui dont l'estate nomme ses bases : l'application DOSSIER
// couvre les bases nommées d'après DOSSIER, sur les trois moteurs. Aucun nom
// d'hôte n'est donc écrit en dur, et la couverture reste vraie quand la graine
// change.
// ---------------------------------------------------------------------------
function entitiesFor (estate, token, level) {
   const out = [];

   for (const db of estate.oracle.databases) {
      if (db.app !== token) continue;
      if (level === 'HOST') {
         out.push({ type: 'HOST', platform: 'ORACLE', host: db.host.hostname });
      } else if (level === 'INSTANCE') {
         out.push({ type: 'INSTANCE', platform: 'ORACLE', host: db.host.hostname, instance: db.sid });
      } else {
         for (const e of db.dbEntities) {
            out.push({ type: 'DATABASE', platform: 'ORACLE', host: db.host.hostname,
                       instance: db.sid, database: e.dimName });
         }
      }
   }

   for (const inst of estate.mssql.instances) {
      const own = inst.databases.filter(x => !x.isSystem && x.name.startsWith(token + '_'));
      if (own.length === 0) continue;
      if (level === 'HOST') {
         out.push({ type: 'HOST', platform: 'MSSQL', host: inst.host.fqdn });
      } else if (level === 'INSTANCE') {
         out.push({ type: 'INSTANCE', platform: 'MSSQL', host: inst.host.fqdn, instance: inst.serverName });
      } else {
         for (const db of own) {
            out.push({ type: 'DATABASE', platform: 'MSSQL', host: inst.host.fqdn,
                       instance: inst.serverName, database: db.name });
         }
      }
   }

   for (const h of estate.postgres.hosts) {
      if (!h.databases.includes(token.toLowerCase())) continue;
      // Un standby réplique les bases de son primaire : le rattacher aussi
      // reviendrait à compter deux fois la même application. L'attachement suit
      // la base, pas sa copie.
      if (h.role === 'STANDBY') continue;
      if (level === 'HOST') {
         out.push({ type: 'HOST', platform: 'POSTGRES', host: h.hostname });
      } else if (level === 'INSTANCE') {
         // Côté PostgreSQL l'instance porte le nom de l'hôte : la collecte ne
         // distingue pas les deux (voir pkg_dbinv_inventory).
         out.push({ type: 'INSTANCE', platform: 'POSTGRES', host: h.hostname, instance: h.hostname });
      } else {
         out.push({ type: 'DATABASE', platform: 'POSTGRES', host: h.hostname,
                    instance: h.hostname, database: token.toLowerCase() });
      }
   }

   // Un HOST peut sortir plusieurs fois si plusieurs entités le désignent.
   const seen = new Set();
   return out.filter(e => {
      const k = [e.type, e.platform, e.host, e.instance, e.database].join('|');
      if (seen.has(k)) return false;
      seen.add(k);
      return true;
   });
}

const LEVEL = { host: 'HOST', instance: 'INSTANCE', database: 'DATABASE' };

function resolveSql (e) {
   if (e.type === 'HOST') {
      return [
         '   select h.host_id into l_entity',
         '     from dim_host h',
         `    where h.platform = ${q(e.platform)}`,
         `      and lower(h.hostname) = lower(${q(e.host)});`];
   }
   if (e.type === 'INSTANCE') {
      return [
         '   select i.instance_id into l_entity',
         '     from dim_instance i',
         '     join dim_host h on h.host_id = i.host_id',
         `    where h.platform = ${q(e.platform)}`,
         `      and lower(h.hostname) = lower(${q(e.host)})`,
         `      and i.instance_name = ${q(e.instance)};`];
   }
   return [
      '   select db.database_id into l_entity',
      '     from dim_database db',
      '     join dim_instance i on i.instance_id = db.instance_id',
      '     join dim_host h on h.host_id = i.host_id',
      `    where h.platform = ${q(e.platform)}`,
      `      and lower(h.hostname) = lower(${q(e.host)})`,
      `      and i.instance_name = ${q(e.instance)}`,
      `      and db.db_name = ${q(e.database)};`];
}

// ---------------------------------------------------------------------------
// Les satellites : groupes, personnes, documents, dépôts.
// ---------------------------------------------------------------------------
function groupLines (app, tpl, domain, out) {
   for (const role of app.roles) {
      const t = tpl[role];
      if (!t) continue;
      const fill = (s) => s === null || s === undefined ? null : s
         .replace(/\{code\}/g, app.code)
         .replace(/\{lcode\}/g, app.code.toLowerCase())
         .replace(/\{vendor\}/g, app.vendor || 'Editeur');
      const mail = fill(t.mail);
      out.push(
         '   l_dummy := pkg_dbinv_application.add_group(',
         '      p_application_id  => l_app,',
         `      p_group_type_code => ${q(role)},`,
         `      p_group_name      => ${q(fill(t.name))},`,
         `      p_contact_email   => ${q(mail === null ? null : mail + '@' + domain)},`,
         `      p_ldap_group_name => ${q(fill(t.ldap))},`,
         `      p_external_ref    => ${q(fill(t.external ?? null))} );`);
   }
}

function contactLines (app, people, idx, domain, out) {
   // Deux personnes par application au plus, prises à la suite dans le vivier.
   // Le vivier tourne : la démonstration montre les mêmes têtes sur plusieurs
   // applications, ce qui est aussi la réalité d'un service d'une trentaine de
   // personnes pour cinq cents bases.
   const roles = app.roles.slice(0, 2);
   roles.forEach((role, k) => {
      const p = people[(idx * 2 + k) % people.length];
      out.push(
         '   l_dummy := pkg_dbinv_application.add_contact(',
         '      p_application_id => l_app,',
         `      p_contact_role   => ${q(role)},`,
         `      p_full_name      => ${q(p.name)},`,
         `      p_job_title      => ${q(p.title)},`,
         `      p_email          => ${q(p.login + '@' + domain)},`,
         `      p_phone          => ${q(p.phone)},`,
         `      p_ldap_login     => ${q(p.login)},`,
         `      p_is_primary     => ${k === 0 ? 1 : 0} );`);
   });
}

// add_document date la prochaine revue mais jamais la précédente : l'API n'écrit
// que le présent, ce qui est juste. Une démonstration a besoin d'un passé, donc
// les états échus sont posés par UPDATE, en le disant.
function documentLines (app, kinds, out) {
   for (const state of app.docs) {
      const k = kinds[state];
      if (!k) continue;
      const months = state === 'unplanned' ? 'null' : '12';
      out.push(
         '   l_doc := pkg_dbinv_application.add_document(',
         '      p_application_id => l_app,',
         `      p_title          => ${q(k.title + ' - ' + app.name)},`,
         `      p_doc_kind       => ${q(k.kind)},`,
         `      p_external_url   => ${q('https://wiki.example.invalid/' + app.code.toLowerCase() + '/' + state)},`,
         `      p_review_months  => ${months} );`);

      if (state === 'current') {
         out.push('   update ref_application_document set last_review_date = trunc(sysdate) - 30,'
                + " last_review_by = 'demo' where document_id = l_doc;");
      } else if (state === 'due-soon') {
         out.push('   update ref_application_document set last_review_date = trunc(sysdate) - 330,'
                + " last_review_by = 'demo', review_due_date = trunc(sysdate) + 20 where document_id = l_doc;");
      } else if (state === 'overdue') {
         out.push('   update ref_application_document set last_review_date = trunc(sysdate) - 400,'
                + " last_review_by = 'demo', review_due_date = trunc(sysdate) - 35 where document_id = l_doc;");
      }
      // 'never' garde une date d'échéance et aucune revue : c'est l'état voulu.
      // 'unplanned' n'a ni l'une ni l'autre, par p_review_months => null.
   }
}

function sourceLines (app, count, out) {
   for (let k = 1; k <= count; k++) {
      out.push(
         '   l_dummy := pkg_dbinv_application.add_source(',
         '      p_application_id => l_app,',
         `      p_repo_url       => ${q('https://git.example.invalid/si/' + app.code.toLowerCase() + (k > 1 ? '-batch' : '') + '.git')},`,
         `      p_source_kind    => 'GIT',`,
         `      p_branch         => ${q(k > 1 ? 'main' : 'production')} );`);
   }
}

// Les quatre états de v_application_overview. Même remarque que pour les
// documents : record_review écrit aujourd'hui, et la démonstration a besoin d'un
// avant et d'un retard.
function reviewLines (state, out) {
   if (state === 'current') {
      out.push('   update ref_application set last_review_date = trunc(sysdate) - 60,'
             + " last_review_by = 'demo', review_due_date = add_months(trunc(sysdate), 10)"
             + ' where application_id = l_app;');
   } else if (state === 'overdue') {
      out.push('   update ref_application set last_review_date = trunc(sysdate) - 400,'
             + " last_review_by = 'demo', review_due_date = trunc(sysdate) - 35"
             + ' where application_id = l_app;');
   } else if (state === 'never') {
      out.push('   update ref_application set last_review_date = null, last_review_by = null,'
             + ' review_due_date = add_months(trunc(sysdate), 3) where application_id = l_app;');
   } else {
      out.push('   update ref_application set last_review_date = null, last_review_by = null,'
             + ' review_due_date = null where application_id = l_app;');
   }
}

export function emitApplications ({ outDir, world, estate }) {
   const cfg = world.applications;
   const domain = world.org.domain;

   const out = [
      '-- Registre applicatif du jeu de demonstration.',
      '-- Genere par fixtures/lib/emit_applications.mjs -- ne pas editer a la main.',
      '--',
      "-- Tout passe par pkg_dbinv_application : ce script exerce l'API que l'ecran",
      '-- utilise, et non un chemin de chargement paralle qui ne prouverait rien.',
      'whenever sqlerror exit failure rollback',
      'set define off',
      'set serveroutput on',
      'declare',
      '   l_app      number;',
      '   l_dummy    number;',
      '   l_doc      number;',
      '   l_entity   number;',
      '   l_existing pls_integer;',
      '   l_apps     pls_integer := 0;',
      '   l_links    pls_integer := 0;',
      'begin',
      // Le registre se saisit, il ne se collecte pas. Recharger les fixtures
      // retruncate le staging et rejoue l'ETL, mais n'a aucune raison d'ecraser
      // ce que quelqu'un a tape dans l'ecran -- et ne le pourrait pas proprement
      // de toute facon, le journal etant append-only. Le script est donc un
      // no-op des que ses applications existent, et il le dit.
      '   select count(*) into l_existing from ref_application',
      `    where app_code in ( ${cfg.catalogue.map(a => q(a.code)).join(', ')} );`,
      '',
      '   if l_existing > 0 then',
      "      dbms_output.put_line('Registre applicatif : deja en place (' || l_existing",
      "         || ' application(s) de demonstration). Rien fait.');",
      "      dbms_output.put_line('  Le registre se saisit et ne se collecte pas : un rechargement');",
      "      dbms_output.put_line('  des fixtures n''ecrase pas une saisie. Pour le regenerer,');",
      "      dbms_output.put_line('  reinstaller le schema (migrate.sh sur un schema vide, ou X_001 hors factory).');",
      '   else'];

   let created = 0, links = 0, groups = 0, contacts = 0, docs = 0, repos = 0;

   cfg.catalogue.forEach((app, idx) => {
      const level = LEVEL[app.attach];
      if (!level) throw new Error(`applications: niveau de rattachement inconnu « ${app.attach} » pour ${app.code}`);
      const entities = entitiesFor(estate, app.app, level);

      out.push(
         '',
         `   -- ${app.code} : ${app.name}`,
         '   l_app := pkg_dbinv_application.create_application(',
         `      p_app_code         => ${q(app.code)},`,
         `      p_app_name         => ${q(app.name)},`,
         `      p_description      => ${q(app.name + ', ' + (app.sourcing === 'INTERNAL' ? 'developpe en interne' : 'progiciel'))},`,
         `      p_criticality      => ${q(app.criticality)},`,
         `      p_lifecycle_status => ${q(app.lifecycle)} );`,
         '   l_apps := l_apps + 1;',
         '   pkg_dbinv_application.set_profile(',
         '      p_application_id   => l_app,',
         `      p_sourcing         => ${q(app.sourcing)},`,
         `      p_vendor_name      => ${q(app.vendor)},`,
         `      p_product_version  => ${q(app.version)},`,
         `      p_support_end_date => ${d(app.supportEnd)},`,
         `      p_rto_minutes      => ${n(app.rto)},`,
         `      p_rpo_minutes      => ${n(app.rpo)},`,
         `      p_service_window   => ${q(app.window)},`,
         `      p_data_sensitivity => ${q(app.sensitivity)},`,
         `      p_register_ref     => ${q(app.register)},`,
         "      p_note             => 'saisi avec le jeu de demonstration' );");

      reviewLines(app.review, out);
      groupLines(app, cfg.groupTemplates, domain, out);
      contactLines(app, cfg.people, idx, domain, out);
      documentLines(app, cfg.docKinds, out);
      sourceLines(app, app.repos, out);

      for (const e of entities) {
         out.push(...resolveSql(e));
         out.push(
            '   l_dummy := pkg_dbinv_application.link_entity(',
            '      p_application_id => l_app,',
            `      p_entity_type    => ${q(e.type)},`,
            '      p_entity_id      => l_entity,',
            `      p_note           => ${q(e.platform + ' ' + e.type.toLowerCase())} );`,
            '   l_links := l_links + 1;');
      }

      created += 1;
      links += entities.length;
      groups += app.roles.length;
      contacts += Math.min(app.roles.length, 2);
      docs += app.docs.length;
      repos += app.repos;
   });

   out.push(
      '',
      "      dbms_output.put_line('Registre applicatif : ' || l_apps || ' application(s), '",
      "         || l_links || ' rattachement(s).');",
      '   end if;',
      '',
      '   commit;',
      'exception',
      '   when no_data_found then',
      '      raise_application_error(-20101,',
      "         'Une entite attendue par le registre applicatif est absente de l''inventaire : '",
      "         || 'l''ETL a-t-il bien tourne avant ce script ?');",
      'end;',
      '/',
      'exit');

   writeFileSync(join(outDir, 'demo_applications.sql'), out.join('\n') + '\n', 'utf8');

   return { applications: created, links, groups, contacts, documents: docs, sources: repos };
}
