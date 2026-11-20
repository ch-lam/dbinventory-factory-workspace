create or replace package pkg_dbinv_inventory as

   -- Tolerant date parser for varchar-typed staging timestamps.
   function safe_to_date ( p_text in varchar2 ) return date;

   procedure load_dimensions;

   procedure load_facts ( p_snapshot_date in date default trunc(sysdate) );

   procedure load_all ( p_snapshot_date in date default trunc(sysdate) );

end pkg_dbinv_inventory;
/
