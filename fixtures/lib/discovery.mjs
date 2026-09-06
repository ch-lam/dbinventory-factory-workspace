// Construction du parc DÉCOUVERT, par opposition au parc collecté.
//
// La discovery et l'inventaire ne voient pas la même chose, et c'est tout
// l'intérêt : la discovery trouve des installations que personne n'a déclarées,
// et rate des machines que l'inventaire collecte pourtant. Ce module fabrique
// les trois populations qui donnent à v_discovery_status ses quatre statuts —
// redécouvert, omis, sauvage, et sauvage déjà trancé.
//
// Il raisonne par HÔTE et traverse les moteurs, là où emit_oracle/mssql/postgres
// raisonnent par moteur : le fichier Linux porte une ligne par machine, couvrant
// PostgreSQL, Oracle et MySQL à la fois.
//
// Aucun tirage ne sort d'ici vers les émetteurs de collecte : ce module reçoit
// son propre flux (world.seed + 404), pour qu'ajouter un hôte sauvage ne décale
// pas les 56 CSV existants et ne réécrive pas la référence.

// Le build RTM d'une version majeure : la discovery Windows lit « Version » à
// la clé d'installation (le RTM) et « Patch » au produit installé. Les deux
// diffèrent, et c'est ce qui permet de voir qu'une instance n'est pas à jour.
const MSSQL_RTM = {
   '11': '11.0.2100.60', '12': '12.0.2000.8', '13': '13.0.1601.5',
   '14': '14.0.1000.169', '15': '15.0.2000.5', '16': '16.0.1000.6',
   '17': '17.0.1000.1'
};

const SERVICE_ACCOUNTS = [
   'NT Service/MSSQLSERVER',
   'NT AUTHORITY/NETWORKSERVICE',
   'NT AUTHORITY/SYSTEM'
];

// La cle de registre ne porte pas le bitness : la discovery a une colonne
// Bitness pour ca. Le parc de collecte, lui, ecrit "Standard Edition (64-bit)"
// parce que c'est ce que rend @@VERSION. Les deux disent la meme chose, et
// c'est la discovery qu'on imite ici.
function registryEdition (edition) {
   return String(edition).replace(/ \(\d+-bit\)$/, '');
}

function rtmOf (build) {
   return MSSQL_RTM[String(build).split('.')[0]] || build;
}

// Un hôte Linux vu par detect_db_engines.sh : trois moteurs, dont ceux qui sont
// absents s'écrivent 'N;0;-;-'. Le producteur n'écrit jamais de champ vide.
function linuxRow (hostn) {
   return {
      hostn,
      pg_pkg: 'N', pg_proc: '0', pg_port: '-', pg_port_guess: '-',
      ora_pkg: 'N', ora_proc: '0', ora_sids: '-', ora_port: '-', ora_port_guess: '-',
      my_pkg: 'N', my_proc: '0', my_port: '-', my_port_guess: '-'
   };
}

function withMysql (row, my) {
   row.my_pkg = 'Y';
   row.my_proc = String(my.procs);
   row.my_port = my.ports;
   row.my_port_guess = my.portGuess;
   return row;
}

export function buildDiscovery (world, estate, rng) {
   const { org } = world;
   const d = world.discovery;
   const fqdn = (h) => (h.includes('.') ? h : `${h}.${org.domain}`);
   const withheld = (engine, i) => (d.withheldHostIndexes[engine] || []).includes(i);

   // ------------------------------------------------------------------ MSSQL
   const mssqlRows = [];
   estate.mssql.hosts.forEach((host, i) => {
      if (withheld('mssql', i)) return;          // -> NOT_SEEN
      for (const inst of host.instances) {
         mssqlRows.push({
            serveur: host.fqdn,
            instance: inst.named ? inst.instTag : 'MSSQLSERVER',
            service: inst.named ? `MSSQL$${inst.instTag}` : 'MSSQLSERVER',
            edition: registryEdition(inst.edition),
            version: rtmOf(inst.build),
            patch: inst.build,
            etatservice: 'Running',
            demarrage: 'Auto',
            compteservice: rng.pick(SERVICE_ACCOUNTS),
            bitness: '64-bit',
            editiongratuite: inst.isFreeEdition ? 'True' : 'False',
            portsql: 'True',
            tcpport: String(inst.port),
            acceswmi: 'OK',
            protocole: 'Dcom',
            statut: 'Detecte (acces complet)',
            detail: ''
         });
      }
   });

   for (const w of d.wild.mssql) {
      mssqlRows.push({
         serveur: fqdn(w.host),
         instance: w.instance,
         service: w.instance === 'MSSQLSERVER' ? 'MSSQLSERVER' : `MSSQL$${w.instance}`,
         edition: registryEdition(w.edition),
         version: rtmOf(w.build),
         patch: w.build,
         etatservice: 'Running',
         demarrage: 'Auto',
         compteservice: rng.pick(SERVICE_ACCOUNTS),
         bitness: '64-bit',
         editiongratuite: /express|developer/i.test(w.edition) ? 'True' : 'False',
         portsql: 'True',
         tcpport: String(w.port),
         acceswmi: 'OK',
         protocole: 'Dcom',
         statut: 'Detecte (acces complet)',
         detail: ''
      });
   }

   // ------------------------------------------------------------------ Linux
   // Une ligne par machine. Les hôtes Oracle du parc portent leurs SID, les
   // hôtes PostgreSQL leur port, et un hôte sauvage peut porter deux moteurs.
   const byHost = new Map();
   const rowFor = (hostn) => {
      if (!byHost.has(hostn)) byHost.set(hostn, linuxRow(hostn));
      return byHost.get(hostn);
   };

   estate.oracle.hosts.forEach((host, i) => {
      if (withheld('oracle', i)) return;         // -> NOT_SEEN
      const dbs = estate.oracle.databases.filter(db => db.host === host);
      if (!dbs.length) return;
      const row = rowFor(fqdn(host.hostname));
      row.ora_pkg = 'Y';
      row.ora_proc = String(dbs.length);
      // Les SID d'une machine se replient en une seule valeur : c'est ce que
      // pkg_dbinv_discovery réexplose en un constat par SID.
      row.ora_sids = dbs.map(db => db.sid).join(',');
      row.ora_port = [...new Set(dbs.map(db => db.port))].sort((a, b) => a - b).join(',');
      row.ora_port_guess = 'N';
   });

   estate.postgres.hosts.forEach((host, i) => {
      if (withheld('postgres', i)) return;       // -> NOT_SEEN
      const row = rowFor(fqdn(host.hostname));
      row.pg_pkg = 'Y';
      row.pg_proc = '1';
      row.pg_port = String(host.port);
      row.pg_port_guess = 'N';
   });

   for (const w of d.wild.oracle) {
      const row = rowFor(fqdn(w.host));
      row.ora_pkg = 'Y';
      row.ora_proc = String(w.procs);
      row.ora_sids = w.sids.length ? w.sids.join(',') : '-';
      row.ora_port = w.ports;
      row.ora_port_guess = w.portGuess;
      if (w.mysql) withMysql(row, w.mysql);
   }

   for (const w of d.wild.postgres) {
      const row = rowFor(fqdn(w.host));
      row.pg_pkg = 'Y';
      row.pg_proc = String(w.procs);
      row.pg_port = w.ports;
      row.pg_port_guess = w.portGuess;
      if (w.mysql) withMysql(row, w.mysql);
   }

   for (const w of d.wild.mysql) withMysql(rowFor(fqdn(w.host)), w);

   const linuxRows = [...byHost.values()].sort((a, b) => a.hostn.localeCompare(b.hostn));

   // ----------------------------------------------------------------- triage
   const triage = d.ignored.map(t => ({
      level: t.level,
      platform: t.platform,
      hostname: fqdn(t.host),
      instance: t.instance || null,
      note: t.note
   }));

   return { runDate: d.runDate, mssqlRows, linuxRows, triage };
}
