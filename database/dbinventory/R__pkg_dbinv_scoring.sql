create or replace package pkg_dbinv_scoring as

   procedure load_findings ( p_snapshot_date in date default trunc(sysdate) );

   procedure apply_exceptions ( p_snapshot_date in date default trunc(sysdate) );

   procedure load_compliance ( p_snapshot_date in date default trunc(sysdate) );

   procedure load_scoring ( p_snapshot_date in date default trunc(sysdate) );

   procedure load_all ( p_snapshot_date in date default trunc(sysdate) );

end pkg_dbinv_scoring;
/
