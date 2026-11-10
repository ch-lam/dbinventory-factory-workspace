-- ============================================================================
-- T_001_apex_page_smoke.sql
-- ----------------------------------------------------------------------------
-- Smoke test for the deployed APEX application, run from the database.
--
-- WHAT THIS IS FOR
--   APEXlang validation proves the .apx compiles. It never opens a page. Page 71
--   passed five validations and still died at first render. This closes part of
--   that gap without needing the front end to be reachable: it inspects what APEX
--   actually holds after an import, and exercises the SQL the pages will run.
--
--   It is the back-end half of the page test. The other half -- really calling
--   the page over HTTP -- needs an ORDS base URL and is not covered here.
--
-- WHAT IT CATCHES
--   1. Region SQL that no longer parses. This is the one that matters most when
--      the model moves: rename a column, and the page breaks with nothing else
--      to warn you. Every region query is parsed against the live schema.
--   2. Items whose plugin attributes were left at a default that breaks the page
--      at render -- today, a fileUpload sitting on storage_type DB_COLUMN with no
--      source, which is exactly the NO_VALID_BLOB_SOURCE failure. The .apx says
--      it -- storage { type: appTempFiles } -- but an item written without the
--      block still imports on DB_COLUMN, and on page 85 nothing else would
--      notice.
--   3. Items pointing at a shared list of values that does not exist.
--   4. Conditions that test an item which does not exist. APEX evaluates them
--      against an empty value without a word, so a button guarded by "item is
--      not null" simply never shows. Fifteen components of pages 81-86 were
--      hidden that way, by an item written @P81_APPLICATION_ID in the .apx: the
--      compiler stored the @ as part of the name, and both validations passed.
--
-- WHAT IT DOES NOT CATCH
--   Anything that only shows up when the page is rendered: template issues,
--   client-side behaviour, dynamic actions, plugin rendering beyond the
--   attributes examined here. A clean run here is necessary, not sufficient.
--
-- USAGE
--   Run it after every import, and on any page whose components changed:
--     sql -S -name <conn> @T_001_apex_page_smoke.sql
--   Optionally narrow to one page:
--     define P_PAGE = 71
--
--   Exits non-zero when a check fails, so it can gate a deployment script.
-- ============================================================================

set serveroutput on size unlimited
set feedback off
set verify off
whenever sqlerror exit failure

define P_APP  = 100
-- leave empty to test every page
define P_PAGE = ""

declare
   c_app      constant number := &P_APP;
   c_page     constant varchar2(10) := '&P_PAGE';
   l_failures pls_integer := 0;
   l_checked  pls_integer := 0;
   l_cur      integer;

   procedure fail ( p_what varchar2, p_where varchar2, p_detail varchar2 ) is
   begin
      l_failures := l_failures + 1;
      dbms_output.put_line('  FAIL  ' || rpad(p_where, 26) || p_what);
      if p_detail is not null then
         dbms_output.put_line('        ' || substr(p_detail, 1, 160));
      end if;
   end fail;

   function in_scope ( p_page number ) return boolean is
   begin
      return c_page is null or c_page = to_char(p_page);
   end in_scope;

begin
   dbms_output.put_line('APEX page smoke test - application ' || c_app
      || case when c_page is not null then ', page ' || c_page else ', all pages' end);
   dbms_output.put_line(rpad('-', 78, '-'));

   -- ---------------------------------------------------------------------
   -- 1. Every region SQL must still parse against the current schema.
   --    Parse only: nothing is executed, so this is safe on any environment.
   -- ---------------------------------------------------------------------
   dbms_output.put_line('1. Region SQL parses');
   for r in ( select page_id, region_name, region_source
                from apex_application_page_regions
               where application_id = c_app
                 and region_source is not null
                 -- the code is 'SQL', not 'SQL_QUERY'; getting this wrong makes
                 -- the loop match nothing and the test pass while checking
                 -- nothing, which is worse than failing
                 and query_type_code = 'SQL'
               order by page_id, region_name ) loop
      if in_scope(r.page_id) then
         l_checked := l_checked + 1;
         l_cur := dbms_sql.open_cursor;
         begin
            -- Bind variables in a page query (:P71_EXCEPTION_ID and friends) are
            -- fine: parsing does not need them resolved.
            dbms_sql.parse(l_cur, r.region_source, dbms_sql.native);
            dbms_sql.close_cursor(l_cur);
         exception
            when others then
               if dbms_sql.is_open(l_cur) then dbms_sql.close_cursor(l_cur); end if;
               fail('region SQL does not parse', 'page ' || r.page_id, r.region_name || ' - ' || sqlerrm);
         end;
      end if;
   end loop;

   -- ---------------------------------------------------------------------
   -- 2. Plugin attributes left on a default that breaks the page.
   --    fileUpload on DB_COLUMN with no source is NO_VALID_BLOB_SOURCE at render.
   -- ---------------------------------------------------------------------
   dbms_output.put_line('2. Item plugin attributes');
   for i in ( select page_id, item_name, display_as, attributes, item_source_type
                from apex_application_page_items
               where application_id = c_app
                 and lower(display_as) like '%file%'
               order by page_id, item_name ) loop
      if in_scope(i.page_id) then
         l_checked := l_checked + 1;
         if json_value(i.attributes, '$.storage_type') = 'DB_COLUMN'
            and nvl(i.item_source_type, 'x') not in ( 'Database Column' ) then
            fail('fileUpload stores into a BLOB column it has no source for',
                 'page ' || i.page_id,
                 i.item_name || ' - add storage { type: appTempFiles } to the item in the .apx, '
                 || 'then import again');
         end if;
      end if;
   end loop;

   -- ---------------------------------------------------------------------
   -- 3. Shared lists of values referenced by items must exist.
   -- ---------------------------------------------------------------------
   dbms_output.put_line('3. Shared LOV references resolve');
   for v in ( select page_id, item_name, lov_named_lov
                from apex_application_page_items
               where application_id = c_app
                 and lov_named_lov is not null
               order by page_id, item_name ) loop
      if in_scope(v.page_id) then
         l_checked := l_checked + 1;
         declare
            l_n pls_integer;
         begin
            select count(*) into l_n from apex_application_lovs
             where application_id = c_app and list_of_values_name = v.lov_named_lov;
            if l_n = 0 then
               fail('shared list of values does not exist', 'page ' || v.page_id,
                    v.item_name || ' references ' || v.lov_named_lov);
            end if;
         end;
      end if;
   end loop;

   -- ---------------------------------------------------------------------
   -- 4. Item-based conditions must name an item that exists. Display and
   --    read-only conditions alike, on every component type that has one.
   --    In a .apx the item is written bare (item: P81_X); written @P81_X it
   --    compiles, imports, and names nothing.
   -- ---------------------------------------------------------------------
   dbms_output.put_line('4. Conditions name existing items');
   for c in ( with conds as (
                 select page_id, 'button ' || button_name what,
                        condition_type_code code, condition_expression1 item
                   from apex_application_page_buttons where application_id = c_app
                 union all
                 select page_id, 'item ' || item_name,
                        condition_type_code, condition_expression1
                   from apex_application_page_items where application_id = c_app
                 union all
                 select page_id, 'item ' || item_name || ' (read-only)',
                        read_only_condition_type_code, read_only_condition_exp1
                   from apex_application_page_items where application_id = c_app
                 union all
                 select page_id, 'region ' || region_name,
                        condition_type_code, condition_expression1
                   from apex_application_page_regions where application_id = c_app
                 union all
                 select page_id, 'region ' || region_name || ' (read-only)',
                        read_only_condition_type_code, read_only_condition_exp1
                   from apex_application_page_regions where application_id = c_app
                 union all
                 select page_id, 'process ' || process_name,
                        condition_type_code, condition_expression1
                   from apex_application_page_proc where application_id = c_app
                 union all
                 select page_id, 'column ' || region_name || '.' || column_alias,
                        condition_type_code, condition_expression1
                   from apex_application_page_rpt_cols where application_id = c_app
                 union all
                 select page_id, 'dynamic action ' || dynamic_action_name,
                        condition_type_code, condition_expression1
                   from apex_application_page_da where application_id = c_app )
              select page_id, what, item
                from conds
               where code in ( 'ITEM_IS_NULL', 'ITEM_IS_NOT_NULL',
                               'ITEM_IS_ZERO', 'ITEM_IS_NOT_ZERO',
                               'ITEM_IS_NULL_OR_ZERO', 'ITEM_NOT_NULL_OR_ZERO',
                               'ITEM_CONTAINS_NO_SPACES', 'ITEM_IS_NUMERIC',
                               'ITEM_IS_NOT_NUMERIC', 'ITEM_IS_ALPHANUMERIC',
                               'VAL_OF_ITEM_IN_COND_EQ_COND2',
                               'VAL_OF_ITEM_IN_COND_NOT_EQ_COND2',
                               'VALUE_OF_ITEM_IN_CONDITION_IN_COLON_DELIMITED_LIST',
                               'VALUE_OF_ITEM_IN_CONDITION_NOT_IN_COLON_DELIMITED_LIST' )
               order by page_id, what ) loop
      if in_scope(c.page_id) then
         l_checked := l_checked + 1;
         declare
            l_n pls_integer;
         begin
            select count(*) into l_n
              from ( select item_name from apex_application_page_items
                      where application_id = c_app
                     union all
                     select item_name from apex_application_items
                      where application_id = c_app )
             where item_name = upper(trim(c.item));
            if l_n = 0 then
               fail('condition tests an item that does not exist', 'page ' || c.page_id,
                    c.what || ' tests "' || c.item || '"'
                    || case when c.item like '@%' then ' - write the item without @ in the .apx' end);
            end if;
         end;
      end if;
   end loop;

   dbms_output.put_line(rpad('-', 78, '-'));
   dbms_output.put_line(l_checked || ' checks run, ' || l_failures || ' failure(s)');

   if l_failures > 0 then
      raise_application_error(-20900,
         l_failures || ' APEX smoke check(s) failed - see the report above.');
   end if;
   dbms_output.put_line('OK');
end;
/

set feedback on
