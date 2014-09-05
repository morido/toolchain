package org.openetcs.sysml2scade.suite.transformation

import com.esterel.scade.api.Package;
import com.esterel.scade.api.util.ScadeModelWriter
import org.eclipse.uml2.uml.Model
import org.eclipse.emf.common.util.URI
import com.esterel.scade.api.ScadePackage
import org.eclipse.emf.common.util.EList
import org.eclipse.uml2.uml.Element
import org.eclipse.emf.common.util.BasicEList
import org.eclipse.papyrus.sysml.blocks.Block
import com.esterel.scade.api.OperatorKind
import org.eclipse.papyrus.sysml.portandflows.FlowPort
import org.eclipse.papyrus.sysml.portandflows.FlowDirection
import org.eclipse.uml2.uml.Type
import org.eclipse.emf.ecore.resource.ResourceSet
import com.esterel.scade.api.ScadeFactory
import org.eclipse.emf.ecore.resource.impl.ResourceSetImpl
import org.eclipse.core.resources.IProject
import com.esterel.project.api.Project
import com.esterel.scade.api.NamedType
import com.esterel.scade.api.Operator
import com.esterel.scade.api.pragmas.editor.EditorPragmasFactory
import com.esterel.scade.api.pragmas.editor.EditorPragmasPackage

class MapToScade extends ScadeModelWriter {
	
	private URI baseURI;
	private ResourceSet sysmlResourceSet;
	private ResourceSet scadeResourceSet;
	private Model sysmlModel;
	private Package scadeModel;
	private Package typePackage;
	private ScadeFactory theScadeFactory;
	private EditorPragmasFactory theEditorPragmasFactory;
	private Project scadeProject;
	
	new(Model model, IProject project) {
		sysmlModel = model;
		sysmlResourceSet = sysmlModel.eResource().getResourceSet();
		scadeResourceSet = new ResourceSetImpl();
		baseURI = URI.createFileURI(project.getLocation().toOSString());
		val projectURI = baseURI.appendSegment(sysmlModel.getName() + ".etp");
		theScadeFactory = ScadePackage.eINSTANCE.getScadeFactory()
		theEditorPragmasFactory = EditorPragmasPackage.eINSTANCE.getEditorPragmasFactory();
		
		// Create empty SCADE project
		scadeProject = createEmptyScadeProject(projectURI, scadeResourceSet);
		
		// Load the create SCADE project
		scadeModel = loadModel(projectURI, scadeResourceSet);
		
		typePackage = createScadePackage("DataDictionary")
		val resource = createXScade("DataDictionary")
		resource.getContents().add(typePackage)
	}
	
	def createXScade(String name) {
		val uriXscade = baseURI.appendSegment(name + ".xscade");
		return scadeResourceSet.createResource(uriXscade);
	} 
	
	def Package createScadePackage(String name) {
		val pkg = theScadeFactory.createPackage()
		pkg.setName(name)
		return pkg
	}
	
	def Package iterateModel(org.eclipse.uml2.uml.Package pkg) {
		val scadePackage = createScadePackage(pkg.name)
		val resourcePackage = createXScade(pkg.name)
		resourcePackage.getContents().add(scadePackage)

		for (block: pkg.getBlocks) {			
			// Each Block is mapped to operator
			val operator = createScadeOperator(block);
			scadePackage.getOperators().add(operator);
			createScadeDiagram(operator);
		}

		for (p : pkg.nestedPackages) {
			scadePackage.getPackages().add(iterateModel(p))
		}

		return scadePackage
	}
	
	def createScadeDiagram(Operator operator) {
		val operator_pragma = theEditorPragmasFactory.createOperator();
		operator.getPragma().add(operator_pragma);
		operator_pragma.setNodeKind("graphical");
		val operator_diagram = theEditorPragmasFactory.createNetDiagram();
		operator_diagram.setName(operator.name + "_diagram");
		operator_diagram.setFormat("A4 (210 297)");
		operator_diagram.setLandscape(true);
		//operator_diagram.setOid("Op1DiagOid");
		operator_pragma.getDiagrams().add(operator_diagram);
	}
	
	def createScadeOperator(Block block) {
			val operator = theScadeFactory.createOperator();
			operator.setName(block.name);
			operator.setKind(OperatorKind.NODE_LITERAL);

			// SysML FlowPorts to operator variables
			for (port : block.flowPorts) {
				var type = createScadeType(port.type)				
				
				// Create the port
				if (port.direction.value == FlowDirection.OUT_VALUE) {
					operator.getOutput().add(createNamedTypeVariable(port.name, type))
				} else if (port.direction.value == FlowDirection.IN_VALUE) {
					operator.getInput().add(createNamedTypeVariable(port.name, type))
				} else if (port.direction.value == FlowDirection.INOUT_VALUE) {
					operator.getInput().add(createNamedTypeVariable("input_" + port.name, type))
					operator.getOutput().add(createNamedTypeVariable("output_" + port.name, type))
				}
			}
			
			return operator;
	}
	
	def createScadeType(Type uml_type) {
		var type_name = "int"
				
		if (uml_type != null && uml_type.name != null) {
			type_name = uml_type.name
		}
		
		var scade_type = findObject(typePackage, type_name, ScadePackage.Literals.TYPE) as com.esterel.scade.api.Type
				
		// If we dont have the type, create
		if (scade_type == null) {
			scade_type = theScadeFactory.createType()
			scade_type.name = type_name
			typePackage.getTypes().add(scade_type)
		}
		
		return scade_type
	}
	
	def createNamedTypeVariable(String name, com.esterel.scade.api.Type type) {
		// Create NamedType
		val namedType = theScadeFactory.createNamedType()
		namedType.setType(type)
		
		// Create Variable
		val variable = theScadeFactory.createVariable()
		variable.setName(name)
		variable.setType(namedType)
		
		return variable
	}
	
	def EList<Block> getBlocks(Element pkg) {
		var list = new BasicEList<Block>
		
		for (Element element: pkg.ownedElements) {
			var stereotype = element.getAppliedStereotype("SysML::Blocks::Block") 
			if (stereotype != null) {
				list.add(element.getStereotypeApplication(stereotype) as Block)
			}
		}
		
		return list
	}
	
	def void fillScadeModel() {
		val pkg = iterateModel(sysmlModel)
		scadeModel.getPackages().add(pkg)
		scadeModel.getPackages().add(typePackage)
		
		// Put annotations in correct .ann file
		rearrangeAnnotations(scadeModel);
		
		// Ensure project contains appropriate FileRefs
		updateProjectWithModelFiles(scadeProject);
		
		// Save the project
		saveAll(scadeProject, null);
	}

	def static EList<Block> getAllBlocks(Model model) {
		var list = new BasicEList<Block>
		
		for (Element element: model.allOwnedElements) {
			var stereotype = element.getAppliedStereotype("SysML::Blocks::Block") 
			if (stereotype != null) {
				list.add(element.getStereotypeApplication(stereotype) as Block)
			}
		}
		
		return list
	}
	
	/**
	 * Function returning the name of a SysML Block
	 * 
	 * @param block The block for which the function return the Name
	 * @return The name of the block
	 */
	def static String name(Block block) {
		return block.base_Class.name
	}
	
	def static String name(FlowPort port) {
		return port.base_Port.name
	}
	
	def static Type type(FlowPort port) {
		return port.base_Port.type
	}
	
	/**
	 * Function returning all FlowPorts of SysML Block
	 * 
	 * @param block The block for which the function returns all FlowPorts
	 * @return List of FlowPorts
	 */
	def static EList<FlowPort> flowPorts(Block block) {
		var list = new BasicEList<FlowPort>
		
		for (port : block.base_Class.ownedPorts) {
			var stereotype = port.getAppliedStereotype("SysML::PortAndFlows::FlowPort")

			if (stereotype != null) {
				list.add(port.getStereotypeApplication(stereotype) as FlowPort)
			}
		}
		
		return list
	}	
}