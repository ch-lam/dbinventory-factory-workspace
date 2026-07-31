--
-- Run ETL and Scoring (after first load of collected data)
--
Begin
  pkg_dbinv_inventory.load_all;
  pkg_dbinv_scoring.load_all;
  commit;
End;
/