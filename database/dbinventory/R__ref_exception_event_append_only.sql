create or replace trigger ref_exception_event_append_only
   before update or delete on ref_exception_event
begin
   raise_application_error(-20010,
      'ref_exception_event is the audit trail of derogations: append-only, no update or delete.');
end;
/
