create or replace trigger ref_application_event_append_only
   before update or delete on ref_application_event
begin
   raise_application_error(-20030,
      'ref_application_event is the audit trail of the application registry: append-only, no update or delete.');
end;
/
