// Construction du parc fictif : hôtes, instances, bases, comptes, stockage.
//
// Aucun nom réel n'entre ici. Les noms de bases évoquent un centre hospitalier
// parce qu'une démo doit ressembler à quelque chose, mais l'établissement est
// inventé et le domaine (.lan) n'est pas routable.
//
// Tout tirage passe par le rng à graine : construire le parc deux fois avec la
// même graine doit donner exactement le même parc, sinon le fichier de
// résultats attendus ne veut rien dire.

const APPS = [
   'PHARMA', 'LABO', 'RADIO', 'DOSSIER', 'PAIE', 'GRH', 'FINANCE', 'STOCK',
   'BLOC', 'URGENCE', 'CONSULT', 'IMAGERIE', 'ANAPATH', 'DIALYSE', 'ONCO',
   'CARDIO', 'NEURO', 'PEDIA', 'MATERN', 'GERIA', 'REHAB', 'NUTRI', 'KINE',
   'ADMIS', 'FACTUR', 'ACHAT', 'BIOMED', 'QUALITE', 'PLANNING', 'TRANSPORT'
];

const OS_LINUX = 'Linux x86 64-bit';
const OS_WIN = 'Windows NT 10.0 x86_64';

// Tire une valeur selon des poids entiers.
function weighted (rng, items, weights) {
   const total = weights.reduce((a, b) => a + b, 0);
   let x = rng.next() * total;
   for (let i = 0; i < items.length; i++) {
      x -= weights[i];
      if (x < 0) return items[i];
   }
   return items[items.length - 1];
}

function envPicker (rng, mix) {
   const codes = Object.keys(mix);
   const weights = codes.map(c => Math.round(mix[c] * 1000));
   return () => weighted(rng, codes, weights);
}

// Marque exactement n éléments d'une liste, de façon déterministe.
//
// On prend un échantillon plutôt qu'un tirage indépendant par élément, pour
// que la part demandée dans world.json soit obtenue EXACTEMENT et non en
// espérance : un test qui compare des comptes au constat près ne tolère pas
// « à peu près 30 % ».
export function markShare (rng, list, share) {
   const n = Math.round(list.length * share);
   const idx = list.map((_, i) => i);
   const marked = new Set(rng.sample(idx, n));
   return list.map((item, i) => ({ item, bad: marked.has(i) }));
}

export function buildEstate (world, rng) {
   const { org } = world;
   const pickEnv = envPicker(rng, world.environments);

   // ---------------------------------------------------------------- Oracle
   const oraHosts = [];
   for (let i = 1; i <= world.oracle.hosts; i++) {
      const env = pickEnv();
      oraHosts.push({
         hostname: `oradb-${env.toLowerCase()}-${String(i).padStart(2, '0')}`,
         environment: env,
         license: rng.pick(world.oracle.licenses),
         numCpus: rng.pick([4, 8, 12, 16, 24, 32]),
         memoryGb: rng.pick([16, 32, 64, 96, 128, 256]),
         osType: OS_LINUX
      });
   }

   const oraNames = rng.shuffle(APPS.slice()).slice(0, world.oracle.databases);
   const oraDbs = oraNames.map((app, i) => {
      const host = oraHosts[i % oraHosts.length];
      const version = weighted(rng, world.oracle.versions, world.oracle.versionWeights);
      const isCdb = rng.chance(world.oracle.cdbShare);
      // Le SID reste court : la colonne accepte 200 caractères, mais un SID
      // Oracle réel tient en 8, et la démo doit rester crédible.
      const suffix = host.environment === 'PRD' ? 'P' : host.environment[0];
      const sid = (app.slice(0, 6) + suffix).slice(0, 8);
      const pdbs = isCdb
         ? Array.from({ length: rng.int(world.oracle.pdbsPerCdb[0], world.oracle.pdbsPerCdb[1]) },
                      (_, k) => `${app.slice(0, 6)}PDB${k + 1}`)
         : [];
      return {
         app, host, sid, dbName: sid, version, isCdb, pdbs,
         environment: host.environment, license: host.license,
         edition: 'Enterprise Edition',
         charset: 'AL32UTF8',
         port: rng.pick([1521, 1521, 1521, 1523, 1526]),
         // Les entités de grain DATABASE, telles que les résoudra l'ETL : une
         // base non-CDB se présente sous 'NON CONTAINER' dans les tables de
         // sécurité, un CDB se présente par PDB.
         dbEntities: isCdb
            ? pdbs.map(p => ({ pdbName: p, dimName: p }))
            : [{ pdbName: 'NON CONTAINER', dimName: sid }]
      };
   });

   // Une base en Standard Edition 2, pour que la règle LMS ait un cas où aucune
   // option n'est licenciable. Choisie sans tirage : consommer le flux partagé
   // ici décalerait tout le parc MSSQL et PostgreSQL construit ensuite.
   const se2 = oraDbs.find(d => !d.isCdb && d.license === 'CPU' && !d.version.startsWith('18'));
   if (se2) se2.edition = 'Standard Edition 2';

   // ---------------------------------------------------------------- MSSQL
   const msHosts = [];
   for (let i = 1; i <= world.mssql.hosts; i++) {
      const env = pickEnv();
      const short = `sqlsrv-${env.toLowerCase()}-${String(i).padStart(2, '0')}`;
      msHosts.push({
         short,
         // collect_target : le FQDN, qui devient dim_host.hostname
         fqdn: `${short}.${org.domain}`,
         environment: env,
         license: rng.pick(world.mssql.licenses),
         numCpus: rng.pick([2, 4, 4, 8, 8, 16]),
         memoryGb: rng.pick([8, 16, 16, 32, 64, 128]),
         osType: OS_WIN,
         instances: []
      });
   }

   const INSTANCE_TAGS = ['SQLEXPRESS', 'FINANCE', 'METIER', 'APPLI', 'GESTION'];
   const msInstances = [];
   for (let i = 0; i < world.mssql.instances; i++) {
      const host = msHosts[i % msHosts.length];
      const named = host.instances.length > 0 || rng.chance(world.mssql.namedInstanceShare);
      // Le tag est choisi parmi ceux que l'hôte n'utilise pas déjà : deux
      // instances homonymes sur une machine se confondraient dans dim_instance,
      // dont la clé naturelle est (host_id, instance_name).
      const free = INSTANCE_TAGS.filter(t => !host.instances.some(x => x.instTag === t));
      const instTag = named ? rng.pick(free) : null;
      // @@SERVERNAME vaut MACHINE ou MACHINE\INSTANCE ; le collecteur réécrit
      // tous les antislashs en slash, donc c'est un slash qui arrive en base.
      const serverName = named ? `${host.short.toUpperCase()}/${instTag}` : host.short.toUpperCase();
      const v = weighted(rng, world.mssql.versions, world.mssql.versions.map(x => x.weight));
      const isFreeEdition = /express|developer/i.test(v.edition);
      // Deux instances SQL Server ne peuvent pas écouter le MÊME port sur une
      // même machine. On tire donc parmi les ports que l'hôte n'utilise pas
      // déjà, 1433 compris — une instance nommée peut légitimement le prendre
      // quand la machine n'a pas d'instance par défaut, et le parc réel en
      // compte onze cas.
      //
      // Sans cette exclusion, une instance nommée pouvait tirer 1433 alors que
      // l'instance par défaut y était : `mssql_collect_list` étant clé sur
      // (hostname, port), les deux se confondaient en une seule ligne de
      // périmètre, et une décision visant l'une s'appliquait à l'autre. Le
      // défaut est resté invisible tant que rien ne consommait le périmètre.
      //
      // `rng.pick` consomme un tirage quelle que soit la taille de la liste :
      // restreindre les candidats ne décale donc aucun tirage en aval.
      const usedPorts = host.instances.map(x => x.port);
      const freePorts = [1433, 49172, 55000, 51433].filter(p => !usedPorts.includes(p));
      const inst = {
         host, named, instTag, serverName,
         port: named ? rng.pick(freePorts) : 1433,
         build: v.build, edition: v.edition, isFreeEdition,
         license: isFreeEdition ? 'FREE' : host.license,
         collation: 'SQL_Latin1_General_CP1_CI_AS',
         environment: host.environment,
         databases: []
      };
      host.instances.push(inst);
      msInstances.push(inst);
   }

   const SYS_DBS = ['master', 'model', 'msdb', 'tempdb'];
   for (const inst of msInstances) {
      const n = rng.int(world.mssql.databasesPerInstance[0], world.mssql.databasesPerInstance[1]);
      const userDbs = rng.sample(APPS, n).map(a => `${a}_${inst.host.environment}`);
      inst.databases = [...SYS_DBS, ...userDbs].map((name, k) => ({
         name, instance: inst, isSystem: SYS_DBS.includes(name), databaseId: k + 1
      }));
   }

   // ---------------------------------------------------------------- Postgres
   const pgHosts = [];
   for (let i = 1; i <= world.postgres.hosts; i++) {
      const env = pickEnv();
      const short = `pgsrv-${env.toLowerCase()}-${String(i).padStart(2, '0')}`;
      const n = rng.int(world.postgres.databasesPerHost[0], world.postgres.databasesPerHost[1]);
      pgHosts.push({
         hostname: `${short}.${org.domain}`,
         environment: env,
         license: 'FREE',
         version: rng.pick(world.postgres.versions),
         port: 5432,
         role: 'PRIMARY',
         databases: rng.sample(APPS, n).map(a => a.toLowerCase())
      });
   }

   // Les derniers hôtes basculent en standby. Ce n'est pas de la décoration :
   // get_info_postgres_security.sh saute les standby, donc une instance standby
   // ne porte AUCUN constat SECURITY. Sans standby dans le jeu, ce comportement
   // -- voulu, et le seul endroit du modèle où une instance collectée n'a pas de
   // verdict de sécurité -- ne serait jamais exercé.
   //
   // Un standby reprend la version ET les bases de son primaire : la réplication
   // est physique, elle copie les blocs. Lui laisser son tirage propre aurait
   // produit un standby portant d'autres bases que celles qu'il réplique, et la
   // page 40 aurait affiché une topologie que rien ne peut produire.
   const nStandby = Math.min(world.postgres.standbys || 0, Math.floor(pgHosts.length / 2));
   for (let k = 0; k < nStandby; k++) {
      const standby = pgHosts[pgHosts.length - 1 - k];
      const primary = pgHosts[k];
      standby.role = 'STANDBY';
      standby.version = primary.version;
      standby.databases = primary.databases.slice();
      standby.replicatesFrom = primary;
   }

   return {
      oracle: { hosts: oraHosts, databases: oraDbs },
      mssql: { hosts: msHosts, instances: msInstances },
      postgres: { hosts: pgHosts }
   };
}
