 $('[data-toggle="modal"]').on('click', function() {
        var targetModal = $(this).data('target');
        $(targetModal).show();
    });

    // Close the modal when the close button is clicked
    $('.close').on('click', function() {
        var modal = $(this).closest('.modal');
        modal.hide();
    });