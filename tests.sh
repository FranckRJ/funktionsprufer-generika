#!/bin/bash

OK_COLOR="\033[1;32m"
ERROR_COLOR="\033[1;31m"
INFO_COLOR="\033[1;33m"
RESET_COLOR="\033[0m"

#Desactivation du globbing parce que ca peut poser probleme et que ca sert a rien pour ce script (je suppose).
set -f

dirToCheck="."
dirToCheckIsCustom="false"
execToCheck=""
authors=""
authorizedFuncs=""
forbidEndingChars="&|/*-+!"
checkAuthorFile="true"
checkNorme="true"
checkAdvancedNorme="true"
checkCodeAuthors="true"
showCodeAuthorsDetail="true"
checkMakefile="true"
checkForbidFunc="true"
defaultCheckAreDisabled="false"
makeFlags=""
makeReFlags=""

function print_help
{
read -r -d '' HELP_TEXT << EOM
DESCRIPTION :
Fait divers tests generiques sur un projet.

Les verifications de norme avancee et des auteurs du code depend de la norme, si la verification
de la norme echoue ces tests ont un compertement indetermine.

La norme avancee peut contenir des faux positifs, son resultat doit etre verifie manuellement.
La liste par defaut des operateurs interdits en fin de ligne est & | / * - + !.

LISTE DES COMMANDES :
<chemin_vers_projet>              Specifie le chemin vers le projet a tester.

--authors / -a <lst>              Specifie la liste des auteurs, avec un ':' comme
                                  separateur. La liste ne peut pas contenir d'espaces.
--exec / -e <name>                Specifie le nom de l'executable du projet.
--funcs / -f <lst>                Specifie la liste des fonctions autorisees.
--forbidendingop / -feo <lst>     Specifie la liste des operateurs interdits en fin de ligne.
--strictendingop / -seo           La liste des operateurs interdits sera remplacee par une liste
                                  plus stricte ( & | / * - + ! , = ).

--noauthorfile / -naf             Desactive la verification du fichier auteur.
--nonorme / -nn                   Desactive la verification de la norme.
--noadvancednorme / -nan          Desactive la verification de la norme avancee.
--nocodeauthors / -nca            Desactive la verification des auteurs du code.
--nocodeauthorsdetail / -ncad     Desactive l'affichage du detail des auteurs du code.
--nomakefile / -nmf               Desactive la verification du Makefile.
--noforbidfunc / -nff             Desactive la verification des fonctions interdites.

--onlyauthorfile / -oaf           Active uniquement la verification du fichier auteur.
--onlynorme / -on                 Active uniquement la verification de la norme.
--onlyadvancednorme / -oan        Active uniquement la verification de la norme avancee.
--onlycodeauthors / -oca          Active uniquement la verification des auteurs du code.
--onlycodeauthorsdetail / -ocad   Active uniquement l'affichage du detail des auteurs du code.
--onlymakefile / -omf             Active uniquement la verification du Makefile.
--onlyforbidfunc / -off           Active uniquement la verification des fonctions interdites.

--makej                           Active l'option -j pour les make normaux.
--makerej                         Active l'option -j pour les make re.
--makeallj                        Active l'option -j pour les make re et normaux.

--help / -h                       Affiche cette page d'aide.
EOM

echo "$HELP_TEXT"
}

function print_error
{
	echo -e -n "$ERROR_COLOR"
	echo -n "$1"
	echo -e "$RESET_COLOR"
}

function print_ok
{
	echo -e -n "$OK_COLOR"
	echo -n "$1"
	echo -e "$RESET_COLOR"
}

function print_info
{
	echo -e -n "$INFO_COLOR"
	echo -n "$1"
	echo -e "$RESET_COLOR"
}

function disable_default_check
{
	if [[ "$defaultCheckAreDisabled" == "false" ]]; then
		checkAuthorFile="false"
		checkNorme="false"
		checkAdvancedNorme="false"
		checkCodeAuthors="false"
		checkMakefile="false"
		checkForbidFunc="false"
		defaultCheckAreDisabled="true"
	fi
}

function check_author_file
{
	errorOccurred="false"
	echo " -------- Fichier auteur :"
	authorFileContent=""
	if [[ -f "$dirToCheck"/auteur ]]; then
		authorFileContent=$(cat "$dirToCheck"/auteur)
	elif [[ -f "$dirToCheck"/author ]]; then
		authorFileContent=$(cat "$dirToCheck"/author)
	else
		print_error "ERREUR : fichier non trouve."
		return
	fi
	if [[ -z $authors ]]; then
		echo "Auteurs non initialises."
		return
	fi
	OIFS="$IFS"
	IFS=':
'
	read -a listOfAuthorsInFileContent <<< $authorFileContent
	IFS=':'
	read  -a listOfAuthors <<< $authors
	IFS="$OIFS"
	listOfAuthorsInFileContent=($listOfAuthorsInFileContent)
	listOfAuthors=($listOfAuthors)
	for author in ${listOfAuthorsInFileContent[@]}; do
		if [[ ! " ${listOfAuthors[@]} " =~ " $author " ]]; then
			print_error "ERREUR : $author n'est pas dans la liste des auteurs."
			errorOccurred="true"
		else
			for i in "${!listOfAuthors[@]}"; do
				if [[ "${listOfAuthors[i]}" == "$author" ]]; then
					unset 'listOfAuthors[i]'
					break
				fi
			done
		fi
	done
	if [[ "${#listOfAuthors[@]}" -gt 0 ]]; then
		print_error "ERREUR : tous les auteurs du projet ne sont pas presents dans le fichier auteur."
	elif [[ "$errorOccurred" == "false" ]]; then
		print_ok "OK."
	fi
}

function check_norme
{
	echo " -------- Norme :"
	if command -v norminette &> /dev/null; then
		normeResult="$(norminette "$dirToCheck" | grep -v "^Warning: Not a valid file" | grep -v "^Norme: ")"
		if [[ -z "$normeResult" ]]; then
			print_ok "OK."
		else
			print_error "ERREUR : "$(echo "$normeResult" | wc -l | tr -d ' ')" erreur(s) de norme."
		fi
	else
		echo "Norminette non presente."
	fi
}

function advanced_norme_check_forbidendingchars
{
	forbidEndingCharsRegex=""
	isFirstCharAdded="true"
	for (( i=0; i<${#forbidEndingChars}; i++ )); do
		if [[ "$isFirstCharAdded" == "false" ]]; then
			forbidEndingCharsRegex="${forbidEndingCharsRegex}|"
		fi
		isFirstCharAdded="false"
		forbidEndingCharsRegex="${forbidEndingCharsRegex}\\${forbidEndingChars:$i:1}"
	done
	findError=$(find "$dirToCheck" \( -name "*.c" -o -name "*.h" \) -print0 |
		while IFS= read -r -d $'\0' codeFile; do
			grepRes="$(tail -n +12 $codeFile | grep -nE '('"$forbidEndingCharsRegex"')$' | grep -vE '^[0-9]*:(\/\*|\*\/)$' | grep -vE '^[0-9]*:\*\*')"
			if [[ ! -z "$grepRes" ]]; then
				print_error "Operateur en fin de ligne dans le fichier ${codeFile} :"
				echo "$grepRes" | perl -ne "/^([0-9]*):[ \t]*(.*)/ && print \"${INFO_COLOR}\",\$1 + 11,\"${RESET_COLOR}: \$2\n\""
			fi
		done)
	if [[ -z "$findError" ]]; then
		return 0
	else
		echo "$findError"
		return 1
	fi
}

function advanced_norme_check_parenthesis
{
	findError=$(find "$dirToCheck" -name "*.h" -print0 |
		while IFS= read -r -d $'\0' codeFile; do
			grepRes="$(tail -n +12 $codeFile | grep -nE '\(\)' | grep -vE '^[0-9]*:(\/\*|\*\/)$' | grep -vE '^[0-9]*:\*\*')"
			if [[ ! -z "$grepRes" ]]; then
				print_error "Parentheses sans contenu dans le fichier ${codeFile} :"
				echo "$grepRes" | perl -ne "/^([0-9]*):[ \t]*(.*)/ && print \"${INFO_COLOR}\",\$1 + 11,\"${RESET_COLOR}: \$2\n\""
			fi
		done)
	if [[ -z "$findError" ]]; then
		return 0
	else
		echo "$findError"
		return 1
	fi
}

function check_advanced_norme
{
	errorFound="false"
	echo " -------- Norme avancee :"
	if ! advanced_norme_check_forbidendingchars; then
		errorFound="true"
	fi
	if ! advanced_norme_check_parenthesis; then
		errorFound="true"
	fi
	if [[ "$errorFound" == "false" ]]; then
		print_ok "OK."
	fi
}

function check_author_of_code
{
	echo " -------- Auteurs du code :"
	if [[ -z $authors ]]; then
		echo "Auteurs non initialises."
		return
	fi
	OIFS="$IFS"
	IFS=':'
	read -a listOfAuthors <<< $authors
	IFS="$OIFS"
	findError=$(find "$dirToCheck" \( -name "*.c" -o -name "*.h" \) -print0 |
		while IFS= read -r -d $'\0' codeFile; do
			listOfAuthorsInCodeFileInString=$(head -n 11 "$codeFile" | perl -ne '/(By\:|by) ([^ ]*)/ && print "$2\n"')
			IFS='
'
			read -a listOfAuthorsInCodeFile <<< $listOfAuthorsInCodeFileInString
			IFS=" "
			for authorInCodeFile in ${listOfAuthorsInCodeFile[@]}; do
				if [[ ! " ${listOfAuthors[@]} " =~ " $authorInCodeFile " ]]; then
					print_error "ERREUR : l'auteur du fichier $codeFile ($authorInCodeFile) n'est pas un auteur du projet."
				fi
			done
		done)
	if [[ -z "$findError" ]]; then
		print_ok "OK."
	else
		echo "$findError"
	fi
}

# $1 = liste des paires clefs / vals, $2 = clef a chercher
function get_val_of_key
{
	valOfKey="$(echo "${1}" | grep -E "^${2}:" | cut -d":" -f2)"
	if [[ -z "$valOfKey" ]]; then
		valOfKey="0"
	fi
	echo "$valOfKey"
}

# $1 = liste des paires clefs / vals, $2 = clef a set, $3 = nouvelle valeur
function set_val_of_key
{
	newList="$(echo "${1}" | grep -vE "^${2}:")"
	newList="$newList
$(echo "${2}:${3}")"
	echo "$newList"
}

function show_detail_author_of_code
{
	createdAuthorList=""
	updatedAuthorList=""
	echo " -------- Detail des auteurs du code :"
	findResult=$(find "$dirToCheck" \( -name "*.c" -o -name "*.h" \) -not -path "$dirToCheck""/libft/*" -print0 |
		(while IFS= read -r -d $'\0' codeFile; do
			createdAuthor="$(head -n 11 "$codeFile" | perl -ne '/Created\:[^b]*by ([^ ]*)/ && print "$1"')"
			updatedAuthor="$(head -n 11 "$codeFile" | perl -ne '/Updated\:[^b]*by ([^ ]*)/ && print "$1"')"

			nbTimesCreatedAuthor="$(get_val_of_key "$createdAuthorList" "$createdAuthor")"
			(( ++nbTimesCreatedAuthor ))
			createdAuthorList="$(set_val_of_key "$createdAuthorList" "$createdAuthor" "$nbTimesCreatedAuthor")"

			nbTimesUpdatedAuthor="$(get_val_of_key "$updatedAuthorList" "$updatedAuthor")"
			(( ++nbTimesUpdatedAuthor ))
			updatedAuthorList="$(set_val_of_key "$updatedAuthorList" "$updatedAuthor" "$nbTimesUpdatedAuthor")"
		done
		print_info "Fichiers crees :"
		echo "${createdAuthorList:1}"
		print_info "Fichiers modifies en dernier :"
		echo "${updatedAuthorList:1}"))
	echo "$findResult"
}

function makefile_check_fclean
{
	if ! make fclean -C "$dirToCheck" &> /dev/null; then
		print_error "ERREUR : la regle fclean n'existe pas."
		return 1
	fi
	if [[ -f "$dirToCheck"/"$execToCheck" ]]; then
		print_error "ERREUR : make fclean ne supprime pas l'executable."
		return 1
	fi
	return 0
}

function makefile_check_clean
{
	execWasHere="false"
	if [[ -f "$dirToCheck"/"$execToCheck" ]]; then
		execWasHere="true"
	fi
	if ! make clean -C "$dirToCheck" &> /dev/null; then
		print_error "ERREUR : la regle clean n'existe pas."
		return 1
	fi
	if [[ "$execWasHere" == "true" ]] && [[ ! -f "$dirToCheck"/"$execToCheck" ]]; then
		print_error "ERREUR : make clean a supprime l'executable."
		return 1
	fi
	return 0
}

# Arg $1 == checkItIsNotRecompiled
function makefile_check_make
{
	execTimestamp=$(date -r "$dirToCheck"/"$execToCheck" 2> /dev/null)
	if [[ "$1" == "true" ]]; then
		sleep 2 #pour etre certain que le nouvel executable a un nouveau timestamp s'il relink.
	fi
	if ! make $makeFlags -C "$dirToCheck" &> /dev/null; then
		print_error "ERREUR : la regle par defaut n'existe pas."
		return 1
	fi
	if [[ ! -f "$dirToCheck"/"$execToCheck" ]]; then
		print_error "ERREUR : make n'a pas cree l'executable."
		return 1
	fi
	if [[ "$1" == "true" ]]; then
		if [[ "$execTimestamp" != $(date -r "$dirToCheck"/"$execToCheck" 2> /dev/null) ]]; then
			print_error "ERREUR : make relink."
			return 1
		fi
	fi
	return 0
}

function makefile_check_all_exist
{
	if ! make $makeFlags all -C "$dirToCheck" &> /dev/null; then
		print_error "ERREUR : la regle all n'existe pas."
		return 1
	fi
	return 0
}

function makefile_check_re
{
	execTimestamp=$(date -r "$dirToCheck"/"$execToCheck" 2> /dev/null)
	sleep 2 #pour etre certain que le nouvel executable a un nouveau timestamp.
	if ! make $makeReFlags re -C "$dirToCheck" &> /dev/null; then
		print_error "ERREUR : la regle re n'existe pas."
		return 1
	fi
	if [[ ! -f "$dirToCheck"/"$execToCheck" ]]; then
		print_error "ERREUR : make re n'a pas cree l'executable."
		return 1
	fi
	if [[ "$execTimestamp" == $(date -r "$dirToCheck"/"$execToCheck" 2> /dev/null) ]]; then
		print_error "ERREUR : make re n'a pas recompile l'executable."
		return 1
	fi
	return 0
}

function check_makefile
{
	echo " -------- Makefile :"
	if [[ ! -f "$dirToCheck"/Makefile ]]; then
		print_error "ERREUR : Makefile non trouve."
		return
	fi
	if [[ -z "$execToCheck" ]]; then
		echo "Executable non initialise."
		return
	fi
	if ! makefile_check_clean; then
		return
	fi
	if ! makefile_check_fclean; then
		return
	fi
	if ! makefile_check_clean; then
		return
	fi
	if ! makefile_check_make false; then
		return
	fi
	if ! makefile_check_make true; then
		return
	fi
	if ! makefile_check_all_exist; then
		return
	fi
	if ! makefile_check_fclean; then
		return
	fi
	if ! makefile_check_re; then
		return
	fi
	if ! makefile_check_clean; then
		return
	fi
	if ! makefile_check_make false; then
		return
	fi
	if ! makefile_check_re; then
		return
	fi
	if ! makefile_check_make true; then
		return
	fi
	if ! makefile_check_clean; then
		return
	fi
	if ! makefile_check_re; then
		return
	fi
	print_ok "OK."
}

function check_forbidden_func
{
	errorOccurred="false"
	echo " -------- Fonctions interdites :"
	if [[ -z "$execToCheck" ]]; then
		echo "Executable non initialise."
		return
	fi
	if [[ ! -f "$dirToCheck"/"$execToCheck" ]]; then
		print_error "ERREUR : executable non trouve."
		return
	fi
	listOfFunctionInString=$(nm -u "$dirToCheck"/"$execToCheck" | grep "^_" | grep -v "^__" | cut -d_ -f2- | cut -d$ -f1)
	read -a listOfFunction <<< $listOfFunctionInString
	read -a listOfAuthorizedFunction <<< $authorizedFuncs
	for func in ${listOfFunction[@]}; do
		if [[ ! " ${listOfAuthorizedFunction[@]} " =~ " $func " ]]; then
			print_error "ERREUR : la fonction $func n'est pas autorisee."
			errorOccurred="true"
		fi
	done
	if [[ "$errorOccurred" == "false" ]]; then
		print_ok "OK."
	fi
}

argv=("$@")
argc="$#"
idx="0"

while [[ "$idx" != "$argc" ]]; do
	param="${argv[$idx]}"
	if [[ "$param" =~ ^-.* ]]; then
		if [[ "$param" == "--help" ]] || [[ "$param" == "-h" ]]; then
			print_help
			exit 0
		elif [[ "$param" == "--authors" ]] || [[ "$param" == "-a" ]]; then
			(( ++idx ))
			param="${argv[$idx]}"
			if [[ -z "$param" ]]; then
				echo "Erreur : le parametre auteurs ne doit pas etre vide."
				exit 0
			else
				if [[ "$param" =~ \  ]]; then
					echo "Erreur : le parametre auteurs ne peut pas contenir d'espaces."
					exit 0
				else
					authors="$param"
				fi
			fi
		elif [[ "$param" == "--exec" ]] || [[ "$param" == "-e" ]]; then
			(( ++idx ))
			param="${argv[$idx]}"
			if [[ -z "$param" ]]; then
				echo "Erreur : le parametre executable ne doit pas etre vide."
				exit 0
			else
				execToCheck="$param"
			fi
		elif [[ "$param" == "--funcs" ]] || [[ "$param" == "-f" ]]; then
			(( ++idx ))
			param="${argv[$idx]}"
			if [[ -z "$param" ]]; then
				echo "Erreur : le parametre fonctions ne doit pas etre vide."
				exit 0
			else
				authorizedFuncs="$param"
			fi
		elif [[ "$param" == "--forbidendingop" ]] || [[ "$param" == "-feo" ]]; then
			(( ++idx ))
			param="${argv[$idx]}"
			if [[ -z "$param" ]]; then
				echo "Erreur : le parametre operateurs interdits en fin de ligne ne doit pas etre vide."
				exit 0
			else
				forbidEndingChars="$param"
			fi
		elif [[ "$param" == "--strictendingop" ]] || [[ "$param" == "-seo" ]]; then
			forbidEndingChars="&|/*-+!,="
		elif [[ "$param" == "--noauthorfile" ]] || [[ "$param" == "-naf" ]]; then
			checkAuthorFile="false"
		elif [[ "$param" == "--nonorme" ]] || [[ "$param" == "-nn" ]]; then
			checkNorme="false"
		elif [[ "$param" == "--noadvancednorme" ]] || [[ "$param" == "-nan" ]]; then
			checkAdvancedNorme="false"
		elif [[ "$param" == "--nocodeauthors" ]] || [[ "$param" == "-nca" ]]; then
			checkCodeAuthors="false"
		elif [[ "$param" == "--nocodeauthorsdetail" ]] || [[ "$param" == "-ncad" ]]; then
			showCodeAuthorsDetail="false"
		elif [[ "$param" == "--nomakefile" ]] || [[ "$param" == "-nmf" ]]; then
			checkMakefile="false"
		elif [[ "$param" == "--noforbidfunc" ]] || [[ "$param" == "-nff" ]]; then
			checkForbidFunc="false"
		elif [[ "$param" == "--onlyauthorfile" ]] || [[ "$param" == "-oaf" ]]; then
			disable_default_check
			checkAuthorFile="true"
		elif [[ "$param" == "--onlynorme" ]] || [[ "$param" == "-on" ]]; then
			disable_default_check
			checkNorme="true"
		elif [[ "$param" == "--onlyadvancednorme" ]] || [[ "$param" == "-oan" ]]; then
			disable_default_check
			checkAdvancedNorme="true"
		elif [[ "$param" == "--onlycodeauthors" ]] || [[ "$param" == "-oca" ]]; then
			disable_default_check
			checkCodeAuthors="true"
		elif [[ "$param" == "--onlycodeauthorsdetail" ]] || [[ "$param" == "-ocad" ]]; then
			disable_default_check
			showCodeAuthorsDetail="true"
		elif [[ "$param" == "--onlymakefile" ]] || [[ "$param" == "-omf" ]]; then
			disable_default_check
			checkMakefile="true"
		elif [[ "$param" == "--onlyforbidfunc" ]] || [[ "$param" == "-off" ]]; then
			disable_default_check
			checkForbidFunc="true"
		elif [[ "$param" == "--makej" ]]; then
			makeFlags="-j"
		elif [[ "$param" == "--makerej" ]]; then
			makeReFlags="-j"
		elif [[ "$param" == "--makeallj" ]]; then
			makeFlags="-j"
			makeReFlags="-j"
		else
			echo "Erreur : parametre $param inconnu. Utilisez --help pour afficher l'aide."
			exit 0
		fi
	else
		if [[ "$dirToCheckIsCustom" == "false" ]]; then
			dirToCheck="$param"
			dirToCheckIsCustom="true"
		else
			echo "Trop d'arguments, le dossier du projet ne peut etre initialise qu'une fois. Utilisez --help pour afficher l'aide."
			exit 0
		fi
	fi
	(( ++idx ))
done

if [[ "$checkAuthorFile" == "true" ]]; then
	check_author_file
fi
if [[ "$checkNorme" == "true" ]]; then
	check_norme
fi
if [[ "$checkAdvancedNorme" == "true" ]]; then
	check_advanced_norme
fi
if [[ "$checkCodeAuthors" == "true" ]]; then
	check_author_of_code
fi
if [[ "$showCodeAuthorsDetail" == "true" ]]; then
	show_detail_author_of_code
fi
if [[ "$checkMakefile" == "true" ]]; then
	check_makefile
fi
if [[ "$checkForbidFunc" == "true" ]]; then
	make $makeFlags -C "$dirToCheck" &> /dev/null
	check_forbidden_func
fi
