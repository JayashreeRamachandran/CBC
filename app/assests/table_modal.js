// Get the modal and button elements
var modal = document.getElementById("myModal");
var openModalBtn = document.getElementById("openModalBtn");
var saveChangesBtn = document.getElementById("saveChangesBtn");

// Get the <span> element that closes the modal
var span = document.getElementsByClassName("close")[0];

// Open the modal when the button is clicked
openModalBtn.onclick = function() {
    modal.style.display = "block";
}

// Close the modal when the close button is clicked
span.onclick = function() {
    modal.style.display = "none";
}

// Close the modal when the user clicks outside of it
window.onclick = function(event) {
    if (event.target == modal) {
        modal.style.display = "none";
    }
}

// Save changes when the "Save Changes" button is clicked
saveChangesBtn.onclick = function() {
    // Add logic to save changes here (e.g., send data to the server)
    modal.style.display = "none"; // Close the modal after saving
}
