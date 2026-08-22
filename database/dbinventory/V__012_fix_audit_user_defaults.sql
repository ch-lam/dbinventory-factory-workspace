-- ============================================================================
-- V__012_fix_audit_user_defaults.sql
-- ----------------------------------------------------------------------------
-- Repoint every audit column at the APEX session user instead of `user`.
--
-- WHY
--   Through APEX the database session runs as APEX_PUBLIC_USER, the pool account
--   shared by every end user. A column defaulting to `user` therefore records
--   APEX_PUBLIC_USER whoever acted -- the same value every time, which is to say
--   no information at all.
--
--   Found in real data: an application created through the screen was attributed
--   to APEX_PUBLIC_USER. Worse, the same defect made the segregation-of-duties
--   constraint on derogations meaningless, because author and approver both
--   resolved to that one account: either every approval was refused, or one was
--   accepted that proved nothing.
--
--   nvl(sys_context('APEX$SESSION','APP_USER'), user) gives the logged-in APEX
--   user inside an APEX session and falls back to the schema outside one, where
--   the schema really is the actor.
--
-- WHY A SEPARATE SCRIPT
--   V__002 and V__010 now create the columns correctly, so a fresh install needs
--   nothing from this file. It exists for schemas already installed, which X_000
--   does not rebuild. Written to be a no-op when the default is already right, so
--   running it twice, or on a fresh install, changes nothing.
--
--   It does NOT rewrite existing rows. A row that recorded APEX_PUBLIC_USER
--   recorded that this was done through the screen by someone unidentified, and
--   inventing a name for it now would be worse than leaving the truth visible.
--
-- ref_app_release.installed_by is deliberately excluded: it dates a deployment
-- run by a script, so the schema user is the right answer there.
-- ============================================================================

alter session set current_schema=dbinventory;

set serveroutput on size unlimited

declare
   c_expr constant varchar2(200) := 'nvl(sys_context(''APEX$SESSION'',''APP_USER''), user)';
   l_done pls_integer := 0;
   l_skip pls_integer := 0;

   -- The columns that record a person. Kept as an explicit list rather than
   -- guessed from column names: a future column called something_by must be
   -- added here on purpose, not swept in by a pattern that also catches
   -- installed_by.
   type t_col is record ( tab varchar2(30), col varchar2(30) );
   type t_cols is table of t_col;
   l_cols t_cols := t_cols(
      t_col('REF_EXCEPTION',            'CREATED_BY'),
      t_col('REF_EXCEPTION_DOCUMENT',   'UPLOADED_BY'),
      t_col('REF_EXCEPTION_EVENT',      'EVENT_BY'),
      t_col('REF_APPLICATION',          'CREATED_BY'),
      t_col('REF_APPLICATION_GROUP',    'CREATED_BY'),
      t_col('REF_APPLICATION_ENTITY',   'CREATED_BY'),
      t_col('REF_APPLICATION_DOCUMENT', 'UPLOADED_BY'),
      t_col('REF_APPLICATION_SOURCE',   'CREATED_BY'),
      t_col('REF_APPLICATION_EVENT',    'EVENT_BY') );

   l_current long;
   l_n       pls_integer;
begin
   for i in 1 .. l_cols.count loop
      select count(*) into l_n
        from user_tab_columns
       where table_name = l_cols(i).tab and column_name = l_cols(i).col;

      if l_n = 0 then
         -- The table is not there yet; a fresh install runs V__002/V__010 first,
         -- so this can only mean the model moved. Say so rather than pass over it.
         dbms_output.put_line('  SKIP  ' || l_cols(i).tab || '.' || l_cols(i).col
                              || ' does not exist');
         l_skip := l_skip + 1;
      else
         select data_default into l_current
           from user_tab_columns
          where table_name = l_cols(i).tab and column_name = l_cols(i).col;

         if l_current is not null and instr(lower(l_current), 'apex$session') > 0 then
            dbms_output.put_line('  ok    ' || l_cols(i).tab || '.' || l_cols(i).col
                                 || ' already correct');
         else
            execute immediate 'alter table ' || l_cols(i).tab
                              || ' modify ( ' || l_cols(i).col
                              || ' default on null ' || c_expr || ' )';
            dbms_output.put_line('  set   ' || l_cols(i).tab || '.' || l_cols(i).col);
            l_done := l_done + 1;
         end if;
      end if;
   end loop;

   dbms_output.put_line(l_done || ' column(s) repointed, ' || l_skip || ' missing');
end;
/

-- ---------------------------------------------------------------------------
-- Recompile what the ALTER TABLE above invalidated.
--
-- Modifying a column invalidates every object that depends on the table -- here
-- the append-only trigger on ref_exception_event. Nothing is wrong with it; it
-- simply has to be recompiled, and Oracle would do it lazily on first use.
--
-- Doing it here rather than leaving it to chance, because T_003 runs at the end
-- of X_000 and reports an INVALID object as a failed install. It is right to do
-- so: an object left invalid by a migration is a migration that did not finish.
-- ---------------------------------------------------------------------------
declare
   l_n pls_integer := 0;
begin
   for o in ( select object_type, object_name from user_objects
               where status <> 'VALID'
               order by case object_type when 'PACKAGE' then 1 when 'PACKAGE BODY' then 2 else 3 end,
                        object_name ) loop
      begin
         if o.object_type = 'PACKAGE BODY' then
            execute immediate 'alter package ' || o.object_name || ' compile body';
         else
            execute immediate 'alter ' || o.object_type || ' ' || o.object_name || ' compile';
         end if;
         l_n := l_n + 1;
      exception when others then
         -- Report and continue: something that will not compile is a real defect,
         -- and T_003 is about to name it with its error text.
         dbms_output.put_line('  WARN  ' || o.object_type || ' ' || o.object_name
                              || ' would not recompile - ' || substr(sqlerrm, 1, 100));
      end;
   end loop;
   dbms_output.put_line(l_n || ' object(s) recompiled after the column changes');
end;
/
