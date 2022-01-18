 #!/usr/bin/python

import networkx as nx
from networkx.algorithms import isomorphism

# prend environ 45 secondes pour atteindre le nombre d'hydrocarbures de formule C7H16

def print_molecule(mol) :
	for bond in mol.edges :
		print(f"{mol._node[bond[0]]['atom']}({bond[0]}) --> {mol._node[bond[1]]['atom']}({bond[1]})")

methane = nx.Graph()
methane.add_nodes_from([
	(0, {"atom":"C"}),
	(1, {"atom":"H"}),
	(2, {"atom":"H"}),
	(3, {"atom":"H"}),
	(4, {"atom":"H"}),
])

methane.add_edges_from([
	(0,1),
	(0,2),
	(0,3),
	(0,4),
])

hydrocarbures = [[methane]]	# hydrocarbure index == number of carbons - 1, contains array of all CnH2n+2

def substitutions_hydrogen_methyl (hydrocarbures) :
	new_hydrocarbures = []
	for hydrocarbure in hydrocarbures :
		hydrogen_carbon = []				# list of hydrogen nodes that bonds to a carbon

		for node in hydrocarbure.nodes :
			if hydrocarbure._node[node]["atom"] == "H" :
				for bond in [bond for bond in hydrocarbure.edges if bond[0] == node or bond[1] == node] :
					if hydrocarbure._node[bond[0]]["atom"] == "C" or hydrocarbure._node[bond[1]]["atom"] == "C" :
						hydrogen_carbon.append(node)

		for hydrogen in hydrogen_carbon :

			new_hydrocarbure = hydrocarbure.copy()
			new_hydrocarbure._node[hydrogen]["atom"] = "C"
			
			next_node = len(hydrocarbure.nodes)
			new_hydrocarbure.add_nodes_from([
				(next_node + 1, {"atom":"H"}),
				(next_node + 2, {"atom":"H"}),
				(next_node + 3, {"atom":"H"}),
			])
			new_hydrocarbure.add_edges_from([
				(hydrogen, next_node + 1),
				(hydrogen, next_node + 2),
				(hydrogen, next_node + 3),
			])

			found_identical_molecule = 0

			for mol in new_hydrocarbures :
				GM = isomorphism.GraphMatcher(mol, new_hydrocarbure)
				if GM.is_isomorphic() :
					found_identical_molecule = 1
					break

			if not found_identical_molecule :
				new_hydrocarbures.append(new_hydrocarbure)

	return new_hydrocarbures

for i in range(7) :
	hydrocarbures.append(substitutions_hydrogen_methyl(hydrocarbures[-1]))
	print(" C %d H %d --> %s molecules" % (i+1, 2*(i+1)+2, len(hydrocarbures[i])))

