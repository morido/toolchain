package org.openetcs.sysml2scade.transformation

class MapToWorkspaceFile {
	def static createWorkspace(String name)'''
	Entities_Definitions DEFINITIONS ::= BEGIN
	project_ref ::= SEQUENCE OF {
		SEQUENCE {
			identity oid,
			persist_as string,
			workspace oid
		}
	}
	workspace ::= SEQUENCE OF {
		SEQUENCE {
			identity oid,
			active_project oid
		}
	}
	base ::= SEQUENCE OF {
		SEQUENCE {
			oid_count integer,
			version string
		}
	}
	base ::= {
	{2, ""}
	}
	workspace ::= {
	{"1", "2"}
	}
	project_ref ::= {
	{"2", "�name�.etp", "1"}
	}
	END
	'''
}