ALTER TABLE organizations DROP CONSTRAINT organizations_tenant_type_check;
ALTER TABLE organizations ADD CONSTRAINT organizations_tenant_type_check
  CHECK (tenant_type IN ('internal', 'contractor', 'supplier'));

INSERT INTO organizations (name, tenant_type)
VALUES ('Material Matrix', 'supplier')
RETURNING id;
